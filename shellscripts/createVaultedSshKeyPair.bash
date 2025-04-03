#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage(){
  echo "
USAGE:

This script will generate a random password and then an SSH key pair protected by that password, then optionally add it to the file you specify. 
It can either leave the generated key files in place or delete them.

Usage: ./$(basename $0) [varname_prefix] [email] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv) (optional: keepKeys)

Please note:
- The varname_prefix must start with 'vault_'
- If outputToFile contains an environment path (e.g., environment/prod/...), that environment will be 
  used automatically and the specifiedEnv parameter can be omitted
- If you specify both an environment in the path and the specifiedEnv parameter, they must match
- keepKeys can be 'yes' or 'no' (default is 'no')

Examples:
./$(basename $0) vault_github user@example.com
./$(basename $0) vault_github user@example.com environment/dev/group_vars/containers/vault_github_deploy_keys.yml
# Environment 'prod' is automatically detected from the path:
./$(basename $0) vault_github user@example.com environment/prod/group_vars/containers/vault_github_deploy_keys.yml 
# Keep the keys after generation:
./$(basename $0) vault_github user@example.com environment/dev/group_vars/containers/vault_github_deploy_keys.yml dev yes

This will generate a private and public key with variables:
vault_github
vault_github_pub
vault_github_passphrase
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
readonly keepKeys="${5:-no}"

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

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
  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
  --stdin-name $varname)"
writeEncrypted "$encrypted" "$varname" "$outputToFile"

# Generate keys
workDir=/tmp/_keys
rm -rf $workDir
mkdir $workDir
ssh-keygen -t ed25519 -C "$email" -N "$password" -f $workDir/${varname_prefix}

# Write Variables
encryptedPrivKey="$(cat "$workDir/${varname_prefix}" | ansible-vault encrypt_string \
--vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
--stdin-name "${varname_prefix}")"

writeEncrypted "$encryptedPrivKey" "${varname_prefix}" "$outputToFile"

encryptedPubKey="$(cat "$workDir/${varname_prefix}.pub" | ansible-vault encrypt_string \
--vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
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
