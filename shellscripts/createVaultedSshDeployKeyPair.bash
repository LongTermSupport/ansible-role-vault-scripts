#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage(){
  echo "

USAGE:

This script will generate an SSH key pair with no password protection.

You must only use these keys for read only deploy keys (eg read only access to github repo for deployment).

You must never use an unprotected key for SSH access to servers

Usage ./$(basename $0) [varname_prefix] [email] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

Please note, the varname_prefix must start with 'vault_'

e.g

./$(basename $0) dev vault_github_deploy

To generate a private and public key with variables

github_deploy
github_deploy_pub

    "
}

# Usage
if (( $# < 2 ))
then
    usage
    exit 1
fi

# Set variables
readonly varname_prefix="$1"
readonly email="$2"
readonly outputToFile="$(getProjectFilePathCreateIfNotExists "${3:-}")"
readonly specifiedEnv="${4:-$defaultEnv}"

# Source vault top
source ./_vault.inc.bash


# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname_prefix"
assertIsEmailAddress "$email"
validateOutputToFile "$outputToFile" "$varname_prefix"

# Generate keys
workDir=/tmp/_keys
rm -rf $workDir
mkdir $workDir
ssh-keygen -t ed25519 -C "$email" -N "" -f $workDir/${varname_prefix}

# Write Variables
encryptedPrivKey="$(cat "$workDir/${varname_prefix}" | ansible-vault encrypt_string \
--vault-id="$specifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}")"

writeEncrypted "$encryptedPrivKey" "${varname_prefix}" "$outputToFile"

encryptedPubKey="$(cat "$workDir/${varname_prefix}.pub" | ansible-vault encrypt_string \
--vault-id="$specifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}_pub")"

writeEncrypted "$encryptedPubKey" "${varname_prefix}_pub" "$outputToFile"

# Clean up
rm -rf $workDir
