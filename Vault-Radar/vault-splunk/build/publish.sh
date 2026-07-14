#!/usr/bin/env bash
set -euo pipefail

function publish_splunk_app {
  # Arguments:
  #   $1 - Release Version
  #   $2 - Splunk Version Supported
  #   $3 - Application ID

  local PKG_NAME=$1
  local SPLUNK_VERSIONS=$2
  local APP_ID=$3

  command=$(curl -u hashicorpvault:"$SPLUNK_PASSWORD" --retry 5 -f --request POST \
    https://splunkbase.splunk.com/api/v1/app/"$APP_ID"/new_release/ \
    -F "files[]=@/$(pwd)/pkg/$PKG_NAME.tar.gz" \
    -F "filename=$PKG_NAME.tar.gz" -F "splunk_versions=$SPLUNK_VERSIONS" -F "visibility=false" | jq .id)  || return 1
  
  echo "$command"
}

function verify_publish {
  # Arguments:
  #   $1 - Publish ID

  local PUBLISH_ID=$1

  result="fail"

  TIMEOUT=0
  echo "Validating package..."
  until [[ $result = *pass* ]]
  do
      command=$(curl -u hashicorpvault:"$SPLUNK_PASSWORD" --retry 5 -f --silent https://splunkbase.splunk.com/api/v1/package/"$PUBLISH_ID"/) || return 1
      result=$(echo "${command}"| jq .result)
      if (( $TIMEOUT == 10 ))
      then
        echo "Failed to validate uploaded package"
        echo "$command"
        return 1
      else
        sleep $(( TIMEOUT++ ))
      fi
  done

  echo "Package uploaded successfully."
  echo "$command"
  return 0

}

function publish {
  # Arguments:
  #   $1 - Release Version
  #   $2 - Splunk Version Supported
  #   $3 - Application ID

  local PKG_NAME=$1
  local SPLUNK_VERSIONS=$2
  local APP_ID=$3

  PUBLISH_ID=$(publish_splunk_app "$PKG_NAME" "$SPLUNK_VERSIONS" "$APP_ID")
  echo "publish id: $PUBLISH_ID"
  verify_publish "$PUBLISH_ID"
}

$*