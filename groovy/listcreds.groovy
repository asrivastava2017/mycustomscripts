import com.cloudbees.plugins.credentials.Credentials
import com.cloudbees.plugins.credentials.CredentialsProvider

Set<Credentials> allCredentials = new HashSet<Credentials>();
Jenkins.instance.getAllItems(com.cloudbees.hudson.plugins.folder.Folder.class).each{ f ->
 creds = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials(
      com.cloudbees.plugins.credentials.Credentials.class, f)
  allCredentials.addAll(creds)

}
for (c in allCredentials) {
  if (CredentialsProvider.FINGERPRINT_ENABLED) {
    fp = CredentialsProvider.getFingerprintOf(c)
    if (fp) {  
    	fp_str = "Fingerprinted jobs: " + fp.getJobs()
  	} else {
    	fp_str = "(No Fingerprints)"
    }  
  }
  println(c.id + " : " + c.description  + " | " + fp_str)
}
