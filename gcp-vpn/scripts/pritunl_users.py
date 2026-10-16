#!/usr/bin/env python3
"""Automate Pritunl (free edition) user management, per environment.

The free edition has no API, so this script drives the same endpoints the web console
uses: it logs in as an administrator (session cookie + CSRF token) and then creates,
lists, disables, enables or deletes users and downloads their VPN profiles.
These endpoints are not an official API and may change between Pritunl versions,
so run `list` after any Pritunl upgrade to confirm the script still works.

Per-environment folder (--env non-prod | production | ...):
  scripts/users/<env>/enc_user_details.enc  encrypted user list (commit this)
  scripts/users/<env>/pritunl.conf         URL, admin username, org (no secrets; commit this)
  scripts/users/<env>/users.csv            plaintext, only while editing (git-ignored, auto-deleted)
  scripts/users/<env>/profiles/            downloaded profiles (git-ignored: contain private keys)

Encryption is compatible with:
  openssl enc -aes-256-cbc -salt -pbkdf2 -in users.csv -out enc_user_details.enc
  openssl enc -aes-256-cbc -d -pbkdf2 -in enc_user_details.enc -out users.csv
The passphrase is prompted by openssl, or taken from USERS_ENC_PASSPHRASE if set.

Commands:
  create   --env ENV    create users (skips existing), download their profiles.
                        Uses users.csv if present (then encrypts it and deletes it),
                        otherwise decrypts enc_user_details.enc in memory.
  decrypt  --env ENV    write users.csv from enc_user_details.enc, to edit it
  pull     --env ENV    add users that exist on the VPN but not in the file (e.g. created
                        in the console) to users.csv, so the file lists everyone; then
                        review and run 'encrypt'
  encrypt  --env ENV    encrypt users.csv into enc_user_details.enc and delete users.csv
  list     --env ENV
  profiles --env ENV [--user NAME ...]
  disable  --env ENV --user NAME [--user NAME ...]
  enable   --env ENV --user NAME [--user NAME ...]
  delete   --env ENV --user NAME [--user NAME ...] [--yes]

Connection settings, highest priority first:
  flags (--url --username --org --password-secret) > scripts/users/<env>/pritunl.conf
  > environment (PRITUNL_URL PRITUNL_USERNAME PRITUNL_ORG PRITUNL_PASSWORD_SECRET).
  Admin password: --password-secret / PRITUNL_PASSWORD_SECRET (Secret Manager), or PRITUNL_PASSWORD.
  --otp CODE if the admin account has 2FA; --insecure for a self-signed certificate.

CSV format (header required; email and pin optional):
  name,email,pin
  alice,alice@company.com,
"""

import argparse
import csv
import http.cookiejar
import io
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

USERS_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "users")
ENC_NAME = "enc_user_details.enc"
CSV_NAME = "users.csv"
CONF_NAME = "pritunl.conf"
CONF_KEYS = ("PRITUNL_URL", "PRITUNL_USERNAME", "PRITUNL_ORG", "PRITUNL_PASSWORD_SECRET")


class PritunlError(Exception):
    pass


class Pritunl:
    def __init__(self, url, insecure=False):
        self.url = url.rstrip("/")
        ctx = ssl._create_unverified_context() if insecure else ssl.create_default_context()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=ctx),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        )
        self.csrf = None

    def _request(self, method, path, body=None, raw=False):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.url + path, data=data, method=method)
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        if self.csrf:
            req.add_header("Csrf-Token", self.csrf)
        try:
            with self.opener.open(req, timeout=60) as resp:
                payload = resp.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            raise PritunlError(f"{method} {path} -> HTTP {e.code}: {detail}") from None
        except urllib.error.URLError as e:
            raise PritunlError(f"{method} {path} -> {e.reason}") from None
        if raw:
            return payload
        return json.loads(payload) if payload else None

    def login(self, username, password, otp=None):
        body = {"username": username, "password": password}
        if otp:
            body["otp_code"] = otp
        resp = self._request("POST", "/auth/session", body) or {}
        if resp.get("otp_auth") or resp.get("local_otp_auth") or resp.get("yubico_auth"):
            if not resp.get("authenticated", False) and not otp:
                raise PritunlError("Admin account requires a 2FA code: pass --otp")
        state = self._request("GET", "/state")
        self.csrf = (state or {}).get("csrf_token")
        if not self.csrf:
            raise PritunlError("Login failed: no CSRF token returned (check username/password)")

    def org_id(self, name):
        orgs = self._request("GET", "/organization") or []
        for org in orgs:
            if org.get("name") == name:
                return org["id"]
        raise PritunlError(f"Organization '{name}' not found. Existing: {[o.get('name') for o in orgs]}")

    def users(self, org_id):
        resp = self._request("GET", f"/user/{org_id}")
        users = resp.get("users", []) if isinstance(resp, dict) else (resp or [])
        return [u for u in users if u.get("type", "client") == "client"]

    def user_by_name(self, org_id, name):
        for u in self.users(org_id):
            if u.get("name") == name:
                return u
        raise PritunlError(f"User '{name}' not found")

    def create_user(self, org_id, name, email=None, pin=None):
        body = {"name": name, "email": email or None, "disabled": False}
        if pin:
            body["pin"] = pin
        resp = self._request("POST", f"/user/{org_id}", body)
        if isinstance(resp, list) and resp:
            return resp[0]
        return resp

    def set_disabled(self, org_id, user_id, disabled):
        return self._request("PUT", f"/user/{org_id}/{user_id}", {"disabled": disabled})

    def delete_user(self, org_id, user_id):
        return self._request("DELETE", f"/user/{org_id}/{user_id}")

    def download_profile(self, org_id, user, directory):
        links = self._request("GET", f"/data/{org_id}/{user['id']}")
        data = self._request("GET", links["key_url"], raw=True)
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, f"{user['name']}.tar")
        with open(path, "wb") as f:
            f.write(data)
        os.chmod(path, 0o600)  # contains the user's private key
        return path




# --- environment folder, config and encryption ------------------------------------

class Env:
    def __init__(self, name):
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
            raise PritunlError(f"Invalid --env '{name}' (use e.g. non-prod or production)")
        self.name = name
        self.dir = os.path.join(USERS_ROOT, name)
        self.enc = os.path.join(self.dir, ENC_NAME)
        self.csv = os.path.join(self.dir, CSV_NAME)
        self.conf = os.path.join(self.dir, CONF_NAME)
        self.profiles = os.path.join(self.dir, "profiles")

    def load_conf(self):
        values = {}
        if os.path.isfile(self.conf):
            with open(self.conf) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        if key.strip() in CONF_KEYS:
                            values[key.strip()] = value.strip().strip('"').strip("'")
        return values


def _openssl_pass_args():
    # Without -pass, openssl prompts on the terminal (twice when encrypting).
    return ["-pass", "env:USERS_ENC_PASSPHRASE"] if os.environ.get("USERS_ENC_PASSPHRASE") else []


def decrypt_to_text(env):
    if not os.path.isfile(env.enc):
        raise PritunlError(f"{env.enc} not found")
    print(f"Decrypting {os.path.relpath(env.enc)}", file=sys.stderr)
    try:
        result = subprocess.run(
            ["openssl", "enc", "-aes-256-cbc", "-d", "-pbkdf2", "-in", env.enc] + _openssl_pass_args(),
            stdout=subprocess.PIPE, check=True,
        )
    except FileNotFoundError:
        raise PritunlError("openssl not found on PATH") from None
    except subprocess.CalledProcessError:
        raise PritunlError("Decryption failed (wrong passphrase or corrupted file)") from None
    return result.stdout.decode()


def encrypt_csv(env):
    """Encrypt users.csv into enc_user_details.enc (atomically), then delete users.csv."""
    if not os.path.isfile(env.csv):
        raise PritunlError(f"{env.csv} not found")
    tmp = env.enc + ".tmp"
    print(f"Encrypting {os.path.relpath(env.csv)} -> {os.path.relpath(env.enc)}", file=sys.stderr)
    try:
        subprocess.run(
            ["openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-in", env.csv, "-out", tmp]
            + _openssl_pass_args(),
            check=True,
        )
        os.replace(tmp, env.enc)
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise PritunlError(f"Encryption failed ({e}); {env.csv} was kept") from None
    os.remove(env.csv)
    print(f"Deleted {os.path.relpath(env.csv)}", file=sys.stderr)


def decrypt_to_csv(env):
    if os.path.exists(env.csv):
        raise PritunlError(f"{env.csv} already exists; edit it, or delete it first")
    text = decrypt_to_text(env)
    fd = os.open(env.csv, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    print(f"Wrote {os.path.relpath(env.csv)} (git-ignored). Run 'encrypt' or 'create' when done.")


def write_csv(env, rows):
    fd = os.open(env.csv, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["name", "email", "pin"])
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in ("name", "email", "pin")})


def write_user_details(directory, row):
    """<name>.details.csv next to the profile: this user's name,email,pin only."""
    path = os.path.join(directory, f"{row['name']}.details.csv")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # may contain a PIN
    with os.fdopen(fd, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["name", "email", "pin"])
        w.writeheader()
        w.writerow({k: row.get(k, "") for k in ("name", "email", "pin")})
    return path


def parse_csv(text):
    rows = list(csv.DictReader(io.StringIO(text)))
    if not rows or "name" not in rows[0]:
        raise PritunlError("User list must be CSV with a header row containing at least 'name'")
    return [
        {"name": r["name"].strip(), "email": (r.get("email") or "").strip(), "pin": (r.get("pin") or "").strip()}
        for r in rows if (r.get("name") or "").strip()
    ]


def get_password(secret):
    if secret:
        try:
            # A full "projects/P/secrets/S" path must be passed as the version resource
            # (gcloud would double the prefix if given via --secret=); a bare name uses
            # the active gcloud project.
            if secret.startswith("projects/"):
                version = secret if "/versions/" in secret else f"{secret}/versions/latest"
                cmd = ["gcloud", "secrets", "versions", "access", version]
            else:
                cmd = ["gcloud", "secrets", "versions", "access", "latest", f"--secret={secret}"]
            return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()
        except OSError as e:
            raise PritunlError(f"Could not run gcloud to read secret {secret}: {e}") from None
        except subprocess.CalledProcessError as e:
            reason = (e.stderr or "").strip() or f"exit status {e.returncode}"
            raise PritunlError(f"Could not read secret {secret}:\n  {reason}") from None
    password = os.environ.get("PRITUNL_PASSWORD")
    if not password:
        raise PritunlError("Set PRITUNL_PASSWORD, or PRITUNL_PASSWORD_SECRET / --password-secret")
    return password


# --- main --------------------------------------------------------------------------

def main():
    sys.stdout.reconfigure(line_buffering=True)  # keep stdout/stderr messages in order
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["create", "decrypt", "encrypt", "pull", "list", "profiles", "disable", "enable", "delete"])
    p.add_argument("--env", required=True, help="environment folder under scripts/users/, e.g. non-prod or production")
    p.add_argument("--url")
    p.add_argument("--username")
    p.add_argument("--org", help="Pritunl organization name")
    p.add_argument("--password-secret")
    p.add_argument("--otp")
    p.add_argument("--insecure", action="store_true")
    p.add_argument("--user", action="append", default=[], help="user name (repeatable)")
    p.add_argument("--keep-csv", action="store_true", help="create: don't encrypt/delete users.csv afterwards")
    p.add_argument("--yes", action="store_true", help="don't ask before deleting")
    args = p.parse_args()

    env = Env(args.env)
    if args.command == "decrypt":
        return decrypt_to_csv(env)
    if args.command == "encrypt":
        return encrypt_csv(env)

    conf = env.load_conf()
    setting = lambda flag, key: flag or conf.get(key) or os.environ.get(key)
    url = setting(args.url, "PRITUNL_URL")
    username = setting(args.username, "PRITUNL_USERNAME")
    org_name = setting(args.org, "PRITUNL_ORG")
    secret = setting(args.password_secret, "PRITUNL_PASSWORD_SECRET")
    missing = [n for n, v in (("URL", url), ("username", username), ("org", org_name)) if not v]
    if missing:
        p.error(f"missing {', '.join(missing)}: set them in {os.path.relpath(env.conf)} or pass flags")

    # Read the user list before logging in, so a wrong passphrase fails fast.
    rows, from_plain_csv = None, False
    if args.command == "pull":
        if os.path.isfile(env.csv):
            with open(env.csv) as f:
                rows = parse_csv(f.read())
        elif os.path.isfile(env.enc):
            rows = parse_csv(decrypt_to_text(env))
        else:
            rows = []
    if args.command == "create":
        if os.path.isfile(env.csv):
            print(f"Using {os.path.relpath(env.csv)}", file=sys.stderr)
            with open(env.csv) as f:
                rows = parse_csv(f.read())
            from_plain_csv = True
        else:
            rows = parse_csv(decrypt_to_text(env))

    print(f"[{env.name}] {url} org={org_name}", file=sys.stderr)
    api = Pritunl(url, insecure=args.insecure)
    api.login(username, get_password(secret), args.otp)
    org = api.org_id(org_name)

    if args.command == "pull":
        in_file = {r["name"].lower() for r in rows}
        on_server = api.users(org)
        added = [u for u in on_server if u["name"].lower() not in in_file]
        rows += [{"name": u["name"], "email": u.get("email") or "", "pin": ""} for u in added]
        write_csv(env, rows)
        server_names = {u["name"].lower() for u in on_server}
        pending = [r["name"] for r in rows if r["name"].lower() not in server_names]
        for u in added:
            print(f"added    {u['name']} (from VPN)")
        for name in pending:
            print(f"pending  {name} (in file, not on VPN yet: 'create' will add it)")
        print(f"\n{len(rows)} users in {os.path.relpath(env.csv)} ({len(added)} added from VPN). "
              f"Review/edit it, then run 'encrypt' (or 'create' if you added people).")
        return

    if args.command == "list":
        for u in sorted(api.users(org), key=lambda u: u.get("name", "")):
            status = "disabled" if u.get("disabled") else ("online" if u.get("status") else "offline")
            print(f"{u.get('name', ''):30} {u.get('email') or '':35} {status}")

    elif args.command == "create":
        # Names are compared case-insensitively, and the set grows as users are created,
        # so neither "Alice" vs "alice" nor a name repeated in the CSV makes a duplicate.
        existing = {u["name"].lower() for u in api.users(org)}
        created, skipped = [], []
        for row in rows:
            if row["name"].lower() in existing:
                skipped.append(row["name"])
                continue
            api.create_user(org, row["name"], row["email"], row["pin"])
            existing.add(row["name"].lower())
            created.append(row)
            print(f"created  {row['name']}")
        for name in skipped:
            print(f"skipped  {name} (already exists, left unchanged)")
        for row in created:
            path = api.download_profile(org, api.user_by_name(org, row["name"]), env.profiles)
            print(f"profile  {row['name']} -> {os.path.relpath(path)}")
            details = write_user_details(env.profiles, row)
            print(f"details  {row['name']} -> {os.path.relpath(details)}")
        print(f"\n{len(created)} created, {len(skipped)} skipped")
        if from_plain_csv and not args.keep_csv:
            encrypt_csv(env)

    elif args.command == "profiles":
        targets = [api.user_by_name(org, n) for n in args.user] if args.user else api.users(org)
        for u in targets:
            print(f"profile  {u['name']} -> {os.path.relpath(api.download_profile(org, u, env.profiles))}")

    elif args.command in ("disable", "enable", "delete"):
        if not args.user:
            p.error(f"{args.command} needs --user")
        users = [api.user_by_name(org, n) for n in args.user]
        if args.command == "delete" and not args.yes:
            answer = input(f"[{env.name}] Delete {', '.join(u['name'] for u in users)} permanently? [y/N] ")
            if answer.strip().lower() != "y":
                print("aborted")
                return
        for u in users:
            if args.command == "delete":
                api.delete_user(org, u["id"])
            else:
                api.set_disabled(org, u["id"], args.command == "disable")
            print(f"{args.command}d {u['name']}")


if __name__ == "__main__":
    try:
        main()
    except PritunlError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
