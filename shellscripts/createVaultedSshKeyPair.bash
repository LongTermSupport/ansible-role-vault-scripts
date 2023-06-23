#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage(){
  echo "

USAGE:

This script will generate a random password and then an SSH key pair protected by that password, then optionally add it to the file you specify. Finally it can either leave the generated key files in place or otherwise will delete them

Usage ./$(basename $0) [varname_prefix] [email] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv) (optional: keepKeys)

Please note, the varname_prefix must start with 'vault_'

e.g

./$(basename $0) dev vault_github

To generate a private and public key with variables

github
github_pub

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
readonly specifiedEnv="${4:-$defaultEnv}"
readonly keepKeys="${5:-no}"

# Source vault top
source ./_vault.inc.bash


# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname_prefix"
assertIsEmailAddress "$email"
validateOutputToFile "$outputToFile" "$varname_prefix"
case "$keepKeys" in
  yes)
    echo 'keys will be kept after creation' ;;
  no)
    echo 'keys will be destroyed after creation' ;;
  *)
    echo "Invalid keepKeys option: $keepKeys"
    exit 1 ;;
esac

# SSH Key Password
readonly password="$(./generatePassword.bash)"

#Write out encrypted Password
readonly varname="${varname_prefix}_passphrase"
encrypted="$(echo -n "$password" | ansible-vault encrypt_string \
  --vault-id="$specifiedEnv@$vaultSecretsPath" \
  --stdin-name $varname)"
writeEncrypted "$encrypted" "$varname" "$outputToFile"

# Generate keys
workDir=/tmp/_keys
rm -rf $workDir
mkdir $workDir
ssh-keygen -t ed25519 -C "$email" -N "$password" -f $workDir/${varname_prefix}

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
if [[ "yes" == "$keepKeys" ]]; then
  printf "\n  Keeping generated keys, they are in:\n%s\n\n" "$workDir"
  ls -alh $workDir | grep "$varname_prefix"
  printf "\n\n\n"
  exit 0
fi
rm -rf $workDir
