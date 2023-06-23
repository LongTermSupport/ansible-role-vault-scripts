#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (( $# < 2 ))
then
    echo "

    This script will allow you to create a new vault file based on an existing file. It will parse out all the
    variables and then create new vaulted passwords for each variable

    Usage ./$(basename $0) [pathToFileToParseVarsFrom] [outputToFile] (optional:  specifiedEnv - defaults to $defaultEnv)

e.g

# Copy a dev env file into the prod env, creating new passwords for all variables
./$(basename $0) \
  environment/dev/group_vars/all/vault-passwords.yml \
  environment/prod/group_vars/all/vault-passwords.yml \
  prod

# Copy a dev env file to another dev env file with a new name, creating new passwords for all variables
./$(basename $0) \
  environment/dev/group_vars/all/vault-passwords-for-mysite.com.yml \
  environment/dev/group_vars/all/vault-passwords-for-anothersite.com.yml

    "
    exit 1
fi

# Set variables
pathToFileToParseVarsFrom="$(getFilePath $1)"
outputToFile="$(getProjectFilePathCreateIfNotExists "$2")"
readonly specifiedEnv="${3:-$defaultEnv}"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertFilesExist $pathToFileToParseVarsFrom



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
