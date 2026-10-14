#!/usr/bin/env python3
"""
GCS public-access and least-privilege audit (read-only).

Finds Cloud Storage buckets that anonymous or public users can reach, and
bucket permissions that go beyond least privilege. Nothing is changed: every
finding comes with the gcloud command that would fix it, for you to review
and run yourself.

What it checks, per bucket
  Public access
    - IAM bindings for allUsers (anyone on the internet) or
      allAuthenticatedUsers (anyone with any Google account)
    - Legacy ACLs on the bucket and its default object ACL (when uniform
      bucket-level access is off)
    - A sample of object ACLs (when uniform bucket-level access is off)
    - Optional live probe: an unauthenticated request to list the bucket
  Guardrails
    - Public access prevention (enforced vs. inherited/unspecified)
    - Uniform bucket-level access (on vs. off)
    - Org policy constraints/storage.publicAccessPrevention per project
  Least privilege
    - Principals outside your allowed domains (users, groups, whole domains)
    - Admin/owner-level bucket roles granted to individual users
    - Service accounts from projects outside the audit scope
    - Deleted principals still present in bindings
    - Project-wide legacy convenience grants (projectEditor:/projectViewer:)

Requirements
  - gcloud CLI, authenticated (gcloud auth login, or a service account)
  - Permissions on each project: storage.buckets.list, storage.buckets.get,
    storage.buckets.getIamPolicy; storage.objects.list and storage.objects.get
    for the object-ACL sample; orgpolicy.policy.get for the org-policy check.
    roles/iam.securityReviewer plus roles/storage.objectViewer covers this, or
    roles/storage.admin if you prefer one role.
  - Python 3.8+, standard library only

Usage
  python3 gcs_public_access_audit.py --projects proj-a proj-b
  python3 gcs_public_access_audit.py --all-projects --allowed-domains example.com
  python3 gcs_public_access_audit.py --projects proj-a --probe --sample-objects 20

Outputs (in --out-dir, default ./gcs-audit-<timestamp>)
  findings.csv  one row per issue, with severity, evidence and fix command
  buckets.csv   one row per bucket with its exposure summary
  Console summary; exit code 2 if any finding meets --fail-on (default HIGH)
"""
import argparse
import csv
import datetime as dt
import json
import os
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PUBLIC_MEMBERS = {"allUsers", "allAuthenticatedUsers"}
ACL_PUBLIC_ENTITIES = {"allUsers", "allAuthenticatedUsers"}

# Roles that let the holder write, delete or administer.
WRITE_ROLES = {
    "roles/storage.admin", "roles/storage.objectAdmin", "roles/storage.objectCreator",
    "roles/storage.objectUser", "roles/storage.legacyBucketOwner", "roles/storage.legacyBucketWriter",
    "roles/storage.legacyObjectOwner", "roles/owner", "roles/editor",
}
ADMIN_ROLES = {"roles/storage.admin", "roles/storage.legacyBucketOwner", "roles/owner", "roles/storage.objectAdmin"}

SEVERITY_ORDER = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "INFO": 0}

# Google-managed service agents are expected on buckets and are not flagged.
GOOGLE_MANAGED_SA_HINTS = (
    "gcp-sa-", "@cloudservices.gserviceaccount.com", "@cloudbuild.gserviceaccount.com",
    "@gs-project-accounts.iam.gserviceaccount.com", "@appspot.gserviceaccount.com",
    "@developer.gserviceaccount.com", "@system.gserviceaccount.com",
    "@container-engine-robot.iam.gserviceaccount.com", "@compute-system.iam.gserviceaccount.com",
    "@serverless-robot-prod.iam.gserviceaccount.com", "@dataflow-service-producer-prod.iam.gserviceaccount.com",
)


# --------------------------------------------------------------------------- helpers

def gcloud(args, allow_fail=False):
    """Run a gcloud command and return parsed JSON (or None on allowed failure)."""
    cmd = ["gcloud"] + args + ["--format=json", "--quiet"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except FileNotFoundError:
        sys.exit("gcloud CLI not found. Install the Google Cloud SDK and run 'gcloud auth login'.")
    except subprocess.TimeoutExpired:
        if allow_fail:
            return None
        raise RuntimeError(f"Timed out: {' '.join(cmd)}")
    if out.returncode != 0:
        if allow_fail:
            return None
        raise RuntimeError(out.stderr.strip() or f"Failed: {' '.join(cmd)}")
    text = out.stdout.strip()
    return json.loads(text) if text else None


def dig(obj, *path, default=None):
    """Read a nested key from either the raw API (camelCase) or gcloud's standardised output."""
    for p in path:
        if not isinstance(obj, dict) or p not in obj:
            return default
        obj = obj[p]
    return obj


def first(*vals):
    for v in vals:
        if v is not None:
            return v
    return None


def member_domain(member):
    # user:alice@x.com, group:g@x.com, domain:x.com, serviceAccount:sa@p.iam.gserviceaccount.com
    if ":" not in member:
        return None
    kind, ident = member.split(":", 1)
    if kind == "domain":
        return ident.lower()
    if "@" in ident:
        return ident.split("@", 1)[1].split("?")[0].lower()
    return None


def is_google_managed_sa(member):
    return any(h in member for h in GOOGLE_MANAGED_SA_HINTS)


def sa_project(member):
    # serviceAccount:name@PROJECT.iam.gserviceaccount.com
    ident = member.split(":", 1)[-1]
    if ident.endswith(".iam.gserviceaccount.com"):
        return ident.split("@", 1)[1].replace(".iam.gserviceaccount.com", "")
    return None


def q(s):
    return shlex.quote(s)


# --------------------------------------------------------------------------- collection

def list_projects(args):
    if args.projects:
        return args.projects
    data = gcloud(["projects", "list", "--filter=lifecycleState:ACTIVE"])
    return sorted(p["projectId"] for p in (data or []))


def org_pap_enforced(project):
    data = gcloud(["resource-manager", "org-policies", "describe",
                   "constraints/storage.publicAccessPrevention", f"--project={project}", "--effective"],
                  allow_fail=True)
    if data is None:
        return "unknown"
    return "enforced" if dig(data, "booleanPolicy", "enforced") else "not enforced"


def list_buckets(project):
    return gcloud(["storage", "buckets", "list", f"--project={project}", "--raw"]) or []


def describe_bucket(name):
    return gcloud(["storage", "buckets", "describe", f"gs://{name}", "--raw"], allow_fail=True) or {}


def bucket_iam(name):
    return gcloud(["storage", "buckets", "get-iam-policy", f"gs://{name}"], allow_fail=True)


def sample_object_acls(name, limit):
    objs = gcloud(["storage", "objects", "list", f"gs://{name}", f"--limit={limit}", "--raw"], allow_fail=True) or []
    results = []
    for o in objs[:limit]:
        oname = o.get("name")
        if not oname:
            continue
        acl = o.get("acl")
        if acl is None:
            d = gcloud(["storage", "objects", "describe", f"gs://{name}/{oname}", "--raw"], allow_fail=True) or {}
            acl = d.get("acl", [])
        results.append((oname, acl or []))
    return results


def anonymous_probe(name):
    """Unauthenticated list request. 200 = anyone can list objects."""
    url = f"https://storage.googleapis.com/storage/v1/b/{name}/o?maxResults=1&fields=items/name"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=15) as r:
            return f"LISTABLE (HTTP {r.status})"
    except urllib.error.HTTPError as e:
        return {401: "denied (401)", 403: "denied (403)", 404: "not found (404)"}.get(e.code, f"HTTP {e.code}")
    except Exception as e:  # network or proxy errors
        return f"probe failed: {type(e).__name__}"


# --------------------------------------------------------------------------- analysis

def audit_bucket(project, b, args, scope_projects, org_pap):
    name = b.get("name") or b.get("id")
    findings = []

    def add(sev, check, detail, evidence="", fix=""):
        findings.append({"project": project, "bucket": name, "severity": sev, "check": check,
                         "detail": detail, "evidence": evidence, "fix_command": fix})

    ubla = first(dig(b, "iamConfiguration", "uniformBucketLevelAccess", "enabled"),
                 b.get("uniform_bucket_level_access"))
    pap = first(dig(b, "iamConfiguration", "publicAccessPrevention"), b.get("public_access_prevention"), "unspecified")
    website = first(b.get("website"), b.get("website_config"))
    location = first(b.get("location"), "")

    public_roles = []

    # ---- IAM policy
    policy = bucket_iam(name)
    if policy is None:
        add("INFO", "iam-unreadable", "Could not read the bucket IAM policy (missing storage.buckets.getIamPolicy?).")
        bindings = []
    else:
        bindings = policy.get("bindings", [])

    for bnd in bindings:
        role = bnd.get("role", "")
        cond = bnd.get("condition")
        cond_note = f" (conditional: {cond.get('title', '')})" if cond else ""
        for m in bnd.get("members", []):
            # Public principals
            if m in PUBLIC_MEMBERS:
                public_roles.append(f"{m}:{role}")
                write = role in WRITE_ROLES
                who = "anyone on the internet" if m == "allUsers" else "anyone with any Google account"
                sev = "CRITICAL" if write else "HIGH"
                what = ("administer" if role in ADMIN_ROLES else "upload or change objects") if write else "read"
                add(sev, "public-iam",
                    f"{who} can {what} via {role}{cond_note}.",
                    f"{m} -> {role}",
                    f"gcloud storage buckets remove-iam-policy-binding gs://{q(name)} --member={m} --role={role}")
                continue

            # Deleted principals
            if m.startswith("deleted:"):
                add("LOW", "deleted-principal", f"Binding still references a deleted principal for {role}.",
                    m, f"gcloud storage buckets remove-iam-policy-binding gs://{q(name)} --member={q(m)} --role={role}")
                continue

            # Project-wide legacy convenience grants
            if m.startswith(("projectEditor:", "projectOwner:", "projectViewer:")):
                if m.startswith("projectViewer:") and role in WRITE_ROLES:
                    add("MEDIUM", "convenience-grant",
                        f"Every project viewer gets {role} on this bucket.", f"{m} -> {role}",
                        f"gcloud storage buckets remove-iam-policy-binding gs://{q(name)} --member={m} --role={role}")
                elif args.flag_convenience:
                    add("LOW", "convenience-grant",
                        f"Project-wide role holders inherit {role}; consider explicit, narrower grants.", f"{m} -> {role}")
                continue

            dom = member_domain(m)
            kind = m.split(":", 1)[0]

            # Outside allowed domains
            if args.allowed_domains and kind in ("user", "group", "domain") and dom and dom not in args.allowed_domains:
                sev = "HIGH" if role in WRITE_ROLES else "MEDIUM"
                add(sev, "external-principal",
                    f"{kind} outside the allowed domains has {role}{cond_note}.", f"{m} -> {role}",
                    f"gcloud storage buckets remove-iam-policy-binding gs://{q(name)} --member={q(m)} --role={role}")

            # Whole-domain grants
            if kind == "domain":
                add("MEDIUM" if role in WRITE_ROLES else "LOW", "domain-wide-grant",
                    f"Every account in {dom} has {role}; prefer a group.", f"{m} -> {role}")

            # Admin to individual users
            if kind == "user" and role in ADMIN_ROLES:
                add("MEDIUM", "user-admin",
                    f"Individual user holds {role}; grant admin through a group, and only where needed.",
                    f"{m} -> {role}")

            # Cross-project service accounts
            if kind == "serviceAccount" and not is_google_managed_sa(m):
                sp = sa_project(m)
                if sp and scope_projects and sp not in scope_projects:
                    add("LOW", "foreign-service-account",
                        f"Service account from project '{sp}' (outside the audit scope) has {role}.",
                        f"{m} -> {role}")

    # ---- Guardrails
    effective_pap = "enforced" if (str(pap).lower() == "enforced" or
                                   (str(pap).lower() in ("inherited", "unspecified") and org_pap == "enforced")) else pap
    if effective_pap != "enforced":
        sev = "MEDIUM" if (public_roles or not ubla) else "LOW"
        add(sev, "pap-not-enforced",
            f"Public access prevention is '{pap}'"
            + (f"; org policy is {org_pap}." if org_pap else "."),
            f"publicAccessPrevention={pap}",
            f"gcloud storage buckets update gs://{q(name)} --public-access-prevention")

    acl_public = []
    if ubla is False or ubla is None:
        add("MEDIUM", "ubla-disabled",
            "Uniform bucket-level access is off, so object ACLs can grant access that IAM does not show.",
            "uniformBucketLevelAccess=false",
            f"gcloud storage buckets update gs://{q(name)} --uniform-bucket-level-access")

        full = describe_bucket(name)
        for label, entries, flag in (("bucket ACL", full.get("acl") or [], "--remove-acl-grant"),
                                     ("default object ACL", full.get("defaultObjectAcl") or [],
                                      "--remove-default-object-acl-grant")):
            for e in entries:
                ent = e.get("entity", "")
                if ent in ACL_PUBLIC_ENTITIES:
                    acl_public.append(f"{label}:{ent}:{e.get('role')}")
                    write = e.get("role") in ("WRITER", "OWNER")
                    add("CRITICAL" if write else "HIGH", "public-acl",
                        f"{label} grants {e.get('role')} to {ent}"
                        + (" (new objects will be public)." if label == "default object ACL" else "."),
                        f"{ent}:{e.get('role')}",
                        f"gcloud storage buckets update gs://{q(name)} {flag}={ent}")

        if args.sample_objects > 0:
            public_objs = []
            for oname, acl in sample_object_acls(name, args.sample_objects):
                ents = [a.get("entity") for a in acl if a.get("entity") in ACL_PUBLIC_ENTITIES]
                if ents:
                    public_objs.append((oname, ents[0]))
            if public_objs:
                ex = ", ".join(o for o, _ in public_objs[:5])
                add("HIGH", "public-object-acl",
                    f"{len(public_objs)} of {args.sample_objects} sampled objects are public via object ACL.",
                    ex,
                    f"gcloud storage buckets update gs://{q(name)} --uniform-bucket-level-access  "
                    f"# disables all object ACLs; or per object: gcloud storage objects update gs://{q(name)}/** "
                    f"--remove-acl-grant={public_objs[0][1]}")
                acl_public.append(f"objects:{len(public_objs)}/{args.sample_objects}")

    if website and (public_roles or acl_public):
        add("INFO", "static-website",
            "Bucket is configured as a static website; public read may be intended. Confirm, and keep write private.",
            json.dumps(website))

    probe = ""
    if args.probe:
        probe = anonymous_probe(name)
        if probe.startswith("LISTABLE"):
            add("CRITICAL" if not public_roles else "HIGH", "anonymous-probe",
                "An unauthenticated request could list objects in this bucket.", probe)

    max_sev = max((SEVERITY_ORDER[f["severity"]] for f in findings), default=-1)
    exposure = "PUBLIC" if (public_roles or acl_public or probe.startswith("LISTABLE")) else "private"
    row = {
        "project": project, "bucket": name, "location": location, "exposure": exposure,
        "public_grants": "; ".join(public_roles + acl_public),
        "public_access_prevention": pap if effective_pap == pap else f"{pap} (enforced by org policy)", "uniform_bucket_level_access": ubla,
        "org_policy_pap": org_pap or "", "website": "yes" if website else "",
        "anonymous_probe": probe,
        "highest_severity": next((k for k, v in SEVERITY_ORDER.items() if v == max_sev), "NONE"),
        "finding_count": len(findings),
    }
    return row, findings


# --------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="Read-only audit of GCS buckets for public access and least privilege.")
    scope = ap.add_mutually_exclusive_group(required=True)
    scope.add_argument("--projects", nargs="+", help="project IDs to audit")
    scope.add_argument("--all-projects", action="store_true", help="audit every active project you can see")
    ap.add_argument("--allowed-domains", nargs="*", default=[],
                    help="your organisation's email domains; principals outside them are flagged")
    ap.add_argument("--sample-objects", type=int, default=10,
                    help="objects to check per bucket when uniform access is off (0 to skip; default 10)")
    ap.add_argument("--probe", action="store_true",
                    help="also send an unauthenticated list request to each bucket")
    ap.add_argument("--flag-convenience", action="store_true",
                    help="also report default projectEditor/projectOwner/projectViewer grants")
    ap.add_argument("--skip-org-policy", action="store_true", help="skip the org-policy check")
    ap.add_argument("--workers", type=int, default=8, help="buckets audited in parallel (default 8)")
    ap.add_argument("--out-dir", default=None, help="output folder (default ./gcs-audit-<timestamp>)")
    ap.add_argument("--fail-on", default="HIGH", choices=list(SEVERITY_ORDER) + ["NONE"],
                    help="exit with code 2 if any finding is at or above this severity (default HIGH)")
    args = ap.parse_args()
    args.allowed_domains = [d.lower().lstrip("@") for d in args.allowed_domains]

    out_dir = args.out_dir or f"gcs-audit-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}"
    os.makedirs(out_dir, exist_ok=True)

    projects = list_projects(args)
    scope_projects = set(projects)
    print(f"Auditing {len(projects)} project(s)...", file=sys.stderr)

    rows, findings, errors = [], [], []
    for project in projects:
        try:
            buckets = list_buckets(project)
        except RuntimeError as e:
            msg = str(e).splitlines()[-1] if str(e) else "error"
            errors.append((project, msg))
            print(f"  {project}: skipped ({msg})", file=sys.stderr)
            continue
        org_pap = None if args.skip_org_policy else org_pap_enforced(project)
        print(f"  {project}: {len(buckets)} bucket(s); org policy PAP {org_pap or 'not checked'}", file=sys.stderr)

        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
            for row, fnd in pool.map(lambda b: audit_bucket(project, b, args, scope_projects, org_pap), buckets):
                rows.append(row)
                findings.extend(fnd)

    findings.sort(key=lambda f: (-SEVERITY_ORDER[f["severity"]], f["project"], f["bucket"], f["check"]))
    rows.sort(key=lambda r: (r["exposure"] != "PUBLIC", -SEVERITY_ORDER.get(r["highest_severity"], -1),
                             r["project"], r["bucket"]))

    fpath, bpath = os.path.join(out_dir, "findings.csv"), os.path.join(out_dir, "buckets.csv")
    with open(fpath, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=["severity", "project", "bucket", "check", "detail", "evidence", "fix_command"])
        w.writeheader()
        w.writerows(findings)
    with open(bpath, "w", newline="", encoding="utf-8-sig") as fh:
        cols = ["project", "bucket", "location", "exposure", "public_grants", "public_access_prevention",
                "uniform_bucket_level_access", "org_policy_pap", "website", "anonymous_probe",
                "highest_severity", "finding_count"]
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    # ---- summary
    public = [r for r in rows if r["exposure"] == "PUBLIC"]
    counts = {s: sum(1 for f in findings if f["severity"] == s) for s in SEVERITY_ORDER}
    print("\n=== GCS public access audit ===")
    print(f"Projects audited : {len(projects) - len(errors)} of {len(projects)}")
    print(f"Buckets audited  : {len(rows)}")
    print(f"Public buckets   : {len(public)}")
    print("Findings         : " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    if public:
        print("\nPublicly accessible buckets:")
        for r in public:
            print(f"  [{r['highest_severity']}] {r['project']}/{r['bucket']}  ->  {r['public_grants'] or r['anonymous_probe']}")
    if errors:
        print("\nProjects that could not be read:")
        for p, m in errors:
            print(f"  {p}: {m}")
    print(f"\nReports: {fpath}\n         {bpath}")
    print("No changes were made. Review each fix_command before running it.")

    if args.fail_on != "NONE" and any(SEVERITY_ORDER[f["severity"]] >= SEVERITY_ORDER[args.fail_on] for f in findings):
        sys.exit(2)


if __name__ == "__main__":
    main()
