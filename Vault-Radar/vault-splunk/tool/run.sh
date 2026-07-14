#!/bin/bash

function usage {
  echo Adding an entitlement
  echo ---------------------
  echo usage: $0 1password_username note splunk-user [splunk-user ...]
  echo
  echo Example:
  echo   $0 katek@hashicorp.com "ConHugeCo license #12345" alicek53 bobh98
  echo
  echo "katek authorizes alicek53 and bobh98 (Splunk usernames) with the given note in quotes."
  echo Notes are not optional.
  echo
  echo Revoking an entitlement
  echo -----------------------
  echo usage: $0 1password_username --revoke splunk-user [splunk-user ...]
  exit 1
}

ADDON_ID=5093 # Vault
export PATH=$PATH:/bin
if [ -z "$2" ]
then
  usage
fi

OP_USER="$1"
shift

if [ "$1" = "--revoke" ]
then
  REVOKE=true
  shift
else 
  NOTE="$1"
  shift
  REVOKE=false
  if [ -z "$1" ]
  then 
    usage
  fi
fi

export OP_TOKEN=$(cat /root/.op-session)
if [ -z $OP_TOKEN ] || ! op list vaults --session $OP_TOKEN > /dev/null
then
  OP_TOKEN=$(op signin --raw hashicorp.1password.com $OP_USER)
  if [ $? != 0 ]
  then
    echo 1password signin failed.
    exit 2
  fi
  echo $OP_TOKEN > $HOME/.op-session
fi

echo Signing into Splunk... 1>&2
RES=$(op get item --session $OP_TOKEN --vault "Splunk App For Vault"  "Splunk Vault Account" --fields username,password)
SPLUNK_USER=$(echo $RES|jq -r .username)
SPLUNK_PW=$(echo $RES|jq -r .password)
unset RES
TOKEN=$(curl -s -d "username=$SPLUNK_USER&password=$SPLUNK_PW" https://splunkbase.splunk.com/api/account:login/ | 
  xmlstarlet sel -N my="http://www.w3.org/2005/Atom" -t -v "my:feed/my:id")
if [ -z "$TOKEN" ]
then
  echo "SplunkBase Authentication failed."
  exit 3
fi
unset SPLUNK_USER
unset SPLUNK_PW

if [ "$REVOKE" = "true" ]
then
  echo Revoking... 1>&2
else
  echo Provisioning... 1>&2
fi

while [ ! -z "$1" ]
do
  SPLUNK_USER_TO_AUTH="$1"
  echo -n "$SPLUNK_USER_TO_AUTH: "
  shift
  if [ "$REVOKE" != "true" ]
  then 
    tmpf=$(mktemp)
    cat - << EOF > $tmpf
<?xml version="1.0" encoding="UTF-8"?>
<entitlement>
    <addon_id>$ADDON_ID</addon_id>
    <username>$SPLUNK_USER_TO_AUTH</username>
    <transaction_note>$NOTE</transaction_note>-->
</entitlement>
EOF

    CODE=$(curl -s -f -o /dev/null -w "%{http_code}" -H "X-Auth-Token: $TOKEN" https://splunkbase.splunk.com/api/entitlements/ --data-binary @$tmpf)

    if [ "$CODE" -eq 200 ] || [ "$CODE" -eq 303 ]
    then
      echo Added
    elif [ "$CODE" -eq 409 ]
    then
      echo Entitlement already existed.
    else
      echo Failure: 
      curl  -H "X-Auth-Token: $TOKEN" https://splunkbase.splunk.com/api/entitlements/ --data-binary @$tmpf
    fi
#    rm $tmpf
  else
    CODE=$(curl -s -f -o /dev/null -w "%{http_code}" -H "X-Auth-Token: $TOKEN" -X DELETE https://splunkbase.splunk.com/api/entitlements/$ADDON_ID/latest/$SPLUNK_USER_TO_AUTH)
    if [ "$CODE" -eq 200 ]
    then
      echo Removed
    elif [ "$CODE" -eq 404 ]
    then
      echo Entitlement did not exist
    else
      echo Failure: 
      curl -H "X-Auth-Token: $TOKEN" -X DELETE https://splunkbase.splunk.com/api/entitlements/$ADDON_ID/latest/$SPLUNK_USER_TO_AUTH
    fi
  fi
done
