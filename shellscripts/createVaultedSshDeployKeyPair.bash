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
You must never use an unprotected key for SSH access to servers.

Usage: ./$(basename $0) [varname_prefix] [email] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

Please note:
- The varname_prefix must start with 'vault_'
- If outputToFile contains an environment path (e.g., environment/prod/...), that environment will be 
  used automatically and the specifiedEnv parameter can be omitted
- If you specify both an environment in the path and the specifiedEnv parameter, they must match

Examples:
./$(basename $0) vault_github_deploy user@example.com
./$(basename $0) vault_github_deploy user@example.com environment/dev/group_vars/containers/vault_github_deploy_keys.yml
# Environment 'prod' is automatically detected from the path:
./$(basename $0) vault_gitlab_deploy user@example.com environment/prod/group_vars/containers/vault_github_deploy_keys.yml

This will generate a private and public key with variables:
vault_github_deploy
vault_github_deploy_pub
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
outputToFile="$(getProjectFilePathCreateIfNotExists "${3:-}")"
readonly userSpecifiedEnv="${4:-$defaultEnv}"

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

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
--vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}")"

writeEncrypted "$encryptedPrivKey" "${varname_prefix}" "$outputToFile"

encryptedPubKey="$(cat "$workDir/${varname_prefix}.pub" | ansible-vault encrypt_string \
--vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}_pub")"

writeEncrypted "$encryptedPubKey" "${varname_prefix}_pub" "$outputToFile"

echo "

Keys created

Public key:

$(cat "$workDir/${varname_prefix}.pub")

"

# Clean up
rm -rf $workDir