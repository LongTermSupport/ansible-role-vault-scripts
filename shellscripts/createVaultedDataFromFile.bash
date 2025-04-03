#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage() {
    echo "
USAGE:

This script will create a vaulted string containing the contents of a specified file, then optionally add it to an Ansible vault file

Usage: ./$(basename $0) [varname] [path_to_secret_file] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

Please note, the varname must be prefixed with 'vault_'

Examples:
./$(basename $0) vault_ssh_key ~/.ssh/id_rsa 
./$(basename $0) vault_ssl_cert /etc/ssl/private/example.com.crt environment/dev/group_vars/keymaster/vault_certificates.yml
./$(basename $0) vault_api_token /path/to/token.txt environment/prod/group_vars/api/vault_tokens.yml prod

"
    exit 1
}

# Usage
if (( $# < 2 ))
then
    usage
fi

# Set variables
readonly varname="$1"
readonly pathToFileToEncrypt="$2"
outputToFile="$(getFilePathOrEmptyString "${3:-}")"
readonly userSpecifiedEnv="${4:-$defaultEnv}"

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"


# Create vault string
encrypted="$(cat "$pathToFileToEncrypt" | ansible-vault encrypt_string \
  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"