#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

function usage(){
  echo "

USAGE:

This script will generate a random password and encrypt it, then add it to the file you specify for each environment.


Usage ./$(basename $0) [varname] (optional: outputToFile with _env_ as env placeholder)

Please note, the varname_prefix must start with 'vault_'

e.g

./$(basename $0) vault_my_password

    "
}

# Usage
if (( $# < 1 ))
then
    usage
    exit 1
fi

readonly varname="$1"
outputToFilePlaceholder="${2:-}"
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

