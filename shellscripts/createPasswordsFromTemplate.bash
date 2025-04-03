#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage() {
    echo "
USAGE:

This script creates a new vault file based on an existing file. It parses all the
variables from the source file and creates new random passwords for each variable.

Usage: ./$(basename $0) [pathToFileToParseVarsFrom] [outputToFile] (optional: specifiedEnv - defaults to $defaultEnv)

Please note:
- This script scans an existing vault file and creates new passwords for each variable
- If outputToFile contains an environment path (e.g., environment/prod/...), that environment will be 
  used automatically and the specifiedEnv parameter can be omitted
- If you specify both an environment in the path and the specifiedEnv parameter, they must match

Examples:
# Create new passwords from a template file:
./$(basename $0) environment/dev/group_vars/containers/vault_passwords.yml environment/prod/group_vars/containers/vault_passwords.yml

# Create passwords for another site using the same template:
./$(basename $0) environment/dev/group_vars/containers/vault_passwords.yml environment/dev/group_vars/containers/vault_passwords_site2.yml
    "
    exit 1
}

# Usage
if (( $# < 2 ))
then
    usage
fi

# Set variables
pathToFileToParseVarsFrom="$(getFilePath $1)"
outputToFile="$(getProjectFilePathCreateIfNotExists "$2")"
readonly userSpecifiedEnv="${3:-$defaultEnv}"

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertFilesExist $pathToFileToParseVarsFrom



# Read
readarray -t varnames <<<"$(grep -Po '^([^: #]+)' "$pathToFileToParseVarsFrom" )"

# loop through and add these to the new file
for varname in "${varnames[@]}"; do
    if [[  "" != "$outputToFile" && "" != "$(grep "^$varname:" "$outputToFile")" ]]; then
      echo "$varname already set, skipping, in $outputToFile";
      continue
    fi
    bash ./createVaultedPassword.bash "$varname" "$outputToFile" "$specifiedEnv"
done
