#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

function usage(){
  echo "
USAGE:

This script will generate unique SSH key pairs with no password protection for each environment.

You must only use these keys for read-only deploy keys (e.g., read-only access to GitHub repo for deployment).
You must never use an unprotected key for SSH access to servers.

Usage: ./$(basename $0) [varname_prefix] [email] [outputToFile with _env_ as env placeholder]

Please note:
- The varname_prefix must start with 'vault_'
- The outputToFile parameter must contain '_env_' as a placeholder for the environment name
- This script will replace '_env_' with each available environment name and call createVaultedSshDeployKeyPair.bash for each one
- Each environment gets a unique key pair (not the same key across environments)

Examples:
./$(basename $0) vault_github_deploy user@example.com environment/_env_/group_vars/containers/vault_github_deploy_keys.yml

This will create a unique key pair in every environment, replacing '_env_' with 'dev', 'prod', etc.
Each environment will have these variables:
vault_github_deploy
vault_github_deploy_pub
    "
}

# Usage
if (( $# != 3  ))
then
    usage
    exit 1
fi

readonly varnamePrefix="$1"
readonly email="$2"
outputToFilePlaceholder="$3"
if [[ "$outputToFilePlaceholder" != "" ]]; then
  outputToFilePlaceholder="$(assertContainsPlaceholder "$outputToFilePlaceholder")"
  echo "outputToFilePlaceholder: $outputToFilePlaceholder"
fi

for envName in $allEnvNames; do
  if [[ "$outputToFilePlaceholder" != "" ]]; then
    outputToFile="${outputToFilePlaceholder/$placeholderEnvName/$envName}"
  fi
  ./createVaultedSshDeployKeyPair.bash "$varnamePrefix" "$email" "$outputToFile" "$envName"
done

