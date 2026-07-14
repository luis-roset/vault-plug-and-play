#!/bin/sh
set -x
if [ -z "$2" ] 
then
  echo usage: $0 1password-username [--revoke] splunk-username [splunk-username ...]
  echo
  echo "This script takes two arguments, your 1password username (you'll be prompted for login credentials)"
  echo "and one or more SplunkBase usernames to authorize to access the Splunk App"
  echo
  echo "If --revoke is supplied, the list of users will be removed from app access."
  exit 1
fi

touch $HOME/.op-session
docker run -i -t  --mount type=bind,source=$HOME/.op-session,target=/root/.op-session \
  -v /tmp/com.agilebits.op.0,target:/tmp/com.agilebits.op.0 \
  vault-splunk-docker-local.artifactory.hashicorp.engineering/vault-app-authorize:v1.0.1 "/bin/run.sh" "$@"


