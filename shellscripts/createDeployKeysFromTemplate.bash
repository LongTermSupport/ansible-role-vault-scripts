#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (( $# < 3 ))
then
    echo "

    This script will allow you to create a new vault file based on an existing file. It will parse out all the
    variables and then create new vaulted deploy keys for each variable

    Usage ./$(basename $0) [pathToFileToParseVarsFrom] [email] [outputToFile] (optional:  specifiedEnv - defaults to $defaultEnv)

e.g

# Copy a dev env file into the prod env, creating new deploy keys for all variables
./$(basename $0) \
  environment/dev/group_vars/all/vault-passwords.yml \
  environment/prod/group_vars/all/vault-passwords.yml \
  prod

# Copy a dev env file to another dev env file with a new name, creating new deploy keys for all variables
./$(basename $0) \
  environment/dev/group_vars/all/vault-passwords-for-mysite.com.yml \
  environment/dev/group_vars/all/vault-passwords-for-anothersite.com.yml

    "
    exit 1
fi

# Set variables
pathToFileToParseVarsFrom="$(getFilePath $1)"
readonly email="$2"
outputToFile="$(getProjectFilePathCreateIfNotExists "$3")"
readonly specifiedEnv="${4:-$defaultEnv}"

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
    if [[ "$varname" == *_pub ]]; then
      echo "Skipping pub key"
      continue
    fi
    bash ./createVaultedSshDeployKeyPair.bash "$varname" "$email" "$outputToFile" "$specifiedEnv"
done
