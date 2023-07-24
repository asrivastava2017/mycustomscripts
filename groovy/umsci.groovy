import jenkins.model.*
import hudson.security.*
import hudson.tasks.Mailer

def instance = Jenkins.getInstance()
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
instance.setSecurityRealm(hudsonRealm)

def users = [
  ['username1', 'password1', 'Full Name 1', 'user1@domain.com'],
  ['username2', 'password2', 'Full Name 2', 'user2@domain.com'],
  ['username1', 'password1', 'Full Name 1', 'user1@domain.com']
]

users.each { user ->
  def username = user[0]
  def password = user[1]
  def fullName = user[2]
  def email = user[3]

  hudsonRealm.createAccount(username, password)
  def userObj = User.get(username)
  userObj.setFullName(fullName)
  userObj.addProperty(new Mailer.UserProperty(email))
  userObj.save()
}
