#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (( $# < 2 ))
then
    echo "

    This script will allow you to create a vaulted string that is the contents of the specified file, then optionally add it to the file you specify

    Usage ./$(basename $0) [specifiedEnv] [varname] [path to file] (output to file, defaults to
    dev/null)

e.g

Please note, the varname must be prefixed with 'vault_'

./$(basename $0) ~/ssh/id_rsa dev vault_privkey

    "
    exit 1
fi

# Set variables
readonly specifiedEnv="$1"
readonly varname="$2"
readonly pathToFileToEncrypt="$3"
readonly outputToFile="$(getFilePathOrEmptyString "${4:-}")"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"


# Create vault string
encrypted="$(cat "$pathToFileToEncrypt" | ansible-vault encrypt_string \
  --vault-id="$specifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"