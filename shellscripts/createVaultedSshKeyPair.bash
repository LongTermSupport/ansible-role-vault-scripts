#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (( $# < 3 ))
then
    echo "

    This script will generate a random password and then an SSH key pair protected by that password, then optionally add it to the file you specify. Finally it can either leave the generated key files in place or otherwise will delete them

    Usage ./$(basename $0) [specifiedEnv] [varname_prefix] [email] (optional: outputToFile) (optional: keepKeys)

e.g

./$(basename $0) dev github

To generate a private and public key with variables

github_id_rsa
github_id_rsa_pub

    "
    exit 1
fi

# Set variables
readonly specifiedEnv="$1"
readonly varname_prefix="$2"
readonly email="$3"
readonly outputToFile="$(getProjectFilePathCreateIfNotExists "${4:-}")"
readonly keepKeys="${5:-no}"

# Source vault top
source ./_vault.inc.bash


# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname_prefix"
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
readonly password='=+'"$(openssl rand -base64 32)"

#Write out encrypted Password
readonly varname="${varname_prefix}_id_rsa_passphrase"
encrypted="$(echo -n "$password" | ansible-vault encrypt_string \
  --vault-id="$specifiedEnv@$vaultSecretsPath" \
  --stdin-name $varname)"
writeEncrypted "$encrypted" "$varname" "$outputToFile"

# Generate keys
workDir=/tmp/_keys
rm -rf $workDir
mkdir $workDir
ssh-keygen -t rsa -b 4096 -C "$email" -N "$password" -f $workDir/${varname_prefix}_id_rsa

# Write Variables
encryptedPrivKey="$(cat "$workDir/${varname_prefix}_id_rsa" | ansible-vault encrypt_string \
--vault-id="$specifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}_id_rsa")"

writeEncrypted "$encryptedPrivKey" "${varname_prefix}_id_rsa" "$outputToFile"

encryptedPubKey="$(cat "$workDir/${varname_prefix}_id_rsa.pub" | ansible-vault encrypt_string \
--vault-id="$specifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}_id_rsa_pub")"

writeEncrypted "$encryptedPubKey" "${varname_prefix}_id_rsa_pub" "$outputToFile"

# Clean up
if [[ "yes" == "$keepKeys" ]]; then
  printf "\n  Keeping generated keys, they are in:\n%s\n\n" "$workDir"
  ls -alh $workDir | grep "$varname_prefix"
  printf "\n\n\n"
  exit 0
fi
rm -rf $workDir