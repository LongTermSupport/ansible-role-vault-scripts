#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (( $# < 2 ))
then
    echo "

    This script will allow you to create a vaulted string that is the contents of the specified file, then optionally add it to the file you specify

    Usage ./$(basename $0) [specifiedEnv] [pathToFileToParseVarsFrom] (outputToFile)

e.g

./$(basename $0) ~/ssh/id_rsa dev privkey

    "
    exit 1
fi

# Set variables
readonly specifiedEnv="$1"
readonly pathToFileToParseVarsFrom="$2"
readonly outputToFile="$(getFilePathOrEmptyString "${3:-}")"

# Assertions
readarray -t varnames <<<"$(grep -Po '^([^: #]+)' "$pathToFileToParseVarsFrom" )"

# loop through and add these to the new file
for varname in "${varnames[@]}"; do
    bash ./createVaultedPassword.bash $specifiedEnv $varname $outputToFile
done
