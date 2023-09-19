#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

function usage(){
  echo "

USAGE:

This script will generate an SSH key pair with no password protection, for each environment.

You must only use these keys for read only deploy keys (eg read only access to github repo for deployment).

You must never use an unprotected key for SSH access to servers

Usage ./$(basename $0) [varname_prefix] [email] (optional: outputToFile with _env_ as env placeholder)

Please note, the varname_prefix must start with 'vault_'

e.g

./$(basename $0) vault_github_deploy

To generate a private and public key with variables

github_deploy
github_deploy_pub

    "
}

# Usage
if (( $# < 2 ))
then
    usage
    exit 1
fi

readonly varnamePrefix="$1"
readonly email="$2"
readonly outputToFilePlaceholder="${3:-}"
if [[ "$outputToFilePlaceholder" != "" ]]; then
  assertContainsPlaceholder "$outputToFilePlaceholder"
fi

for envName in $allEnvNames; do
  if [[ "$outputToFilePlaceholder" != "" ]]; then
    outputToFile="${outputToFilePlaceholder/$placeholderEnvName/$envName}"
  fi
  ./createVaultedSshDeployKeyPair.bash "$varnamePrefix" "$email" "$outputToFile" "$envName"
done

