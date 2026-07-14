@echo off

IF "%2"=="" (
  echo usage: %0 1password-username [--revoke] splunk-username [splunk-username ...]
  echo
  echo "This script takes two arguments, your 1password username (you'll be prompted for login credentials)"
  echo "and one or more SplunkBase usernames to authorize to access the Splunk App"
  echo
  echo "If --revoke is supplied, the list of users will be removed from app access."
  set success=false
) else (
  shift
  docker run -i -t vault-splunk-docker-local.artifactory.hashicorp.engineering/vault-app-authorize:v1.0.1 /bin/bash "/bin/run.sh" %*
)

