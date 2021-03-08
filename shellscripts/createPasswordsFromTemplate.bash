#!/usr/bin/env bash
readonly scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$scriptDir" || exit 1

# Usage
if (( $# < 1 ))
then
    echo "

    This script will allow you to create a vaulted string that is the contents of the specified file, then optionally add it to the file you specify

    Usage ./$(basename $0) [pathToFileToParseVarsFrom] (optional: outputToFile) (optional:  specifiedEnv - defaults to $defaultEnv)

e.g

./$(basename $0) ~/ssh/id_rsa dev privkey

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

# Read
readarray -t varnames <<<"$(grep -Po '^([^: #]+)' "$pathToFileToParseVarsFrom" )"

# loop through and add these to the new file
for varname in "${varnames[@]}"; do
    if [[ "" != "$(grep "^$varname" $outputToFile)" ]]; then
      echo "$varname already set, skipping, in $outputToFile";
      continue
    fi
    bash ./createVaultedPassword.bash $specifiedEnv $varname $outputToFile
done
