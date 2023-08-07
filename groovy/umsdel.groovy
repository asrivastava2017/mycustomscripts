import jenkins.model.Jenkins
import hudson.model.User

def usernames = ["","",""]

usernames.each { username ->
    User user = Jenkins.instance.getUser(username)
    if (user != null) {
        user.delete()
        println("User ${username} deleted successfully.")
    } else {
        println("User ${username} not found.")
    }
}
