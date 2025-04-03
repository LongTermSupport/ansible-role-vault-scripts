#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

function usage(){
  echo "
USAGE:

This script will generate a random password and encrypt it, then add it to a file in each environment.

Usage: ./$(basename $0) [varname] [outputToFile with _env_ as env placeholder]

Please note:
- The varname must start with 'vault_'
- The outputToFile parameter must contain '_env_' as a placeholder for the environment name
- This script will replace '_env_' with each available environment name and call createVaultedPassword.bash for each one

Examples:
./$(basename $0) vault_db_password environment/_env_/group_vars/containers/vault_passwords.yml

This will create the password in every environment, replacing '_env_' with 'dev', 'prod', etc.
    "
}

# Usage
if (( $# < 2 ))
then
    usage
    exit 1
fi

readonly varname="$1"
outputToFilePlaceholder="$2"
if [[ "$outputToFilePlaceholder" != "" ]]; then
  outputToFilePlaceholder="$(assertContainsPlaceholder "$outputToFilePlaceholder")"
  echo "outputToFilePlaceholder: $outputToFilePlaceholder"
fi

for envName in $allEnvNames; do
  if [[ "$outputToFilePlaceholder" != "" ]]; then
    outputToFile="${outputToFilePlaceholder/$placeholderEnvName/$envName}"
  fi
  ./createVaultedPassword.bash "$varname" "$outputToFile" "$envName"
done

