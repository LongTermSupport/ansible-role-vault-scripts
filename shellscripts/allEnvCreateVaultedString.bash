#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

function usage(){
  echo "

USAGE:

This script will encrypt the string you specify for each environment and optionally add it to the file you specify.

Usage ./$(basename $0) [varname] [string] (optional: outputToFile with _env_ as env placeholder)

Please note, the varname must be prefixed with 'vault_'

e.g

./$(basename $0) vault_my_secret 'MySecretValue'

    "
}

# Usage
if (( $# < 2 ))
then
    usage
    exit 1
fi

readonly varname="$1"
readonly string="$2"
outputToFilePlaceholder="$3"
if [[ "$outputToFilePlaceholder" != "" ]]; then
  outputToFilePlaceholder="$(assertContainsPlaceholder "$outputToFilePlaceholder")"
  echo "outputToFilePlaceholder: $outputToFilePlaceholder"
fi

for envName in $allEnvNames; do
  if [[ "$outputToFilePlaceholder" != "" ]]; then
    outputToFile="${outputToFilePlaceholder/$placeholderEnvName/$envName}"
  fi
  ./createVaultedString.bash "$varname" "$string" "$outputToFile" "$envName"
done