Vault Splunk App Entitlement Tool
-

This tool helps you entitle a Splunk user to access the Vault 
Splunk App.

Requirements
-
You will need your 1password credentials (secret key, master key, MFA) to run this tool.
The Secret Key and Master Key can be found in the 1Password recovery kit, or in the 1Password desktop app.

You will also need to contact IT-support to request access to the 1Password vault called "Splunk App for Vault"

Installation
-

If you don't have it already, install Docker for your platform and make sure the Docker daemon is running.  

You will need to visit Artifactory and create for yourself an API token:

https://artifactory.hashicorp.engineering/

Navigate to your profile, and create an API Key.  Then, use this API key to
login to the repossitory:

<pre>docker login vault-splunk-docker-local.artifactory.hashicorp.engineering</pre>

After you run the above command you will be prompted for the following:

`username` (this is your Artifactory username which is typically your HC email address)

`password` (the Artifactory API key)


Usage
-

After cloning this repository, change directories to vault-splunk/tool.

**Mac/Unix**:

./splunk-app-authorize.sh *your_HashiCorp_email* *transaction-note* *splunk_username* ...

**Windows**:

splunk-app-authorize.bat *your_HashiCorp_email* *transaction-note* *splunk_username* ...

`*transaction-note*` should give details of the step being undertaken eg.:

`grant access for user janedoe from company AcmeCorp`

---
You may pass more than one splunk username to the tool at a time.

The tool will fetch the bulk of itself from the HashiCorp docker repository and then
begin prompting you for your 1password credentials as follows:

`Enter the Secret Key for <your_HashiCorp_email> at hashicorp.1password.com:` (1Password Secret Key)

`Enter the password for <your_HashiCorp_email> at hashicorp.1password.com:` (1Password Master Key)

`Enter your six-digit authentication code:` (1Password MFA code)



Once signed in it will fetch the 
HashiCorp Splunk credentials and use them to sign into SplunkBase.  Finally, it will 
issue API calls to add the provided usernames to the whitelist for the app.  

Below is what the output will look like upon success:

```
Signing into Splunk...
Provisioning...
<username>: Added
```
Installing Docker on OSX
------------------------

As with Windows and other non-Linux operating systems, Docker needs a linux VM to run on OS X. If you have not installed this or are recieving errors that the docker command cannot connect to the docker daemon, these high level steps will get Docker installed and running.

1. ```brew install docker docker-machine```
2. ```brew cask install virtualbox```
3. Check System Prefences, General and Allow software from "Oracle America, Inc." to run (VirtualBox is maintained by Oracle)
4. ```docker-machine create --driver virtualbox default```
5. ```docker-machine env default``` 
