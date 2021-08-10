#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (( $# < 1 ))
then
    echo "

    This script will allow you to create a new vault file based on an existing file. It will parse out all the
    variables and then create new vaulted passwords for each variable

    Usage ./$(basename $0) [pathToFileToParseVarsFrom] (optional: outputToFile) (optional:  specifiedEnv - defaults to $defaultEnv)

e.g

./$(basename $0) \
  environment/dev/group_vars/all/vault-passwords-for-mysite.com.yml \
  environment/dev/group_vars/all/vault-passwords-for-anothersite.com.yml

    "
    exit 1
fi

# Set variables
readonly pathToFileToParseVarsFrom="$(getFilePath $1)"
readonly outputToFile="$(getFilePathOrEmptyString "${2:-}")"
readonly specifiedEnv="${3:-$defaultEnv}"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertFilesExist $pathToFileToParseVarsFrom

#Create output file
if [[ "" != "$outputToFile" ]]; then
  getProjectFilePathCreateIfNotExists "$outputToFile"
fi

# Read
readarray -t varnames <<<"$(grep -Po '^([^: #]+)' "$pathToFileToParseVarsFrom" )"

# loop through and add these to the new file
for varname in "${varnames[@]}"; do
    if [[  "" != "$outputToFile" && "" != "$(grep "^$varname" "$outputToFile")" ]]; then
      echo "$varname already set, skipping, in $outputToFile";
      continue
    fi
    bash ./createVaultedPassword.bash "$varname" "$outputToFile" "$specifiedEnv"
done
