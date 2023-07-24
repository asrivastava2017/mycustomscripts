import jenkins.model.*
import hudson.security.*
import com.michelin.cio.hudson.plugins.rolestrategy.*
def instance = Jenkins.getInstance()
def users = User.getAll()
