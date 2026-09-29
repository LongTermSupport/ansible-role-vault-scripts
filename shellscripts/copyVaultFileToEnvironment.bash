#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage() {
  echo "
USAGE:

This script copies vault encrypted files between environments, re-encrypting them with the destination environment's vault password.

Note - #THIS IS A BAD IDEA# in most cases!
Unless it is truly necessary, you should probably be using ./createPasswordsFromTemplate.bash instead.
Copying encrypted secrets between environments can reduce security by duplicating sensitive information.

Usage: ./$(basename $0) [sourceEnv] [destEnv] [vaultFilePaths ...]

Parameters:
- sourceEnv: The source environment (e.g., 'dev', 'prod')
- destEnv: The destination environment (e.g., 'dev', 'prod')
- vaultFilePaths: One or more paths to vault files to copy

Examples:
./$(basename $0) dev prod environment/dev/group_vars/containers/vault_ssl_certs.yml
./$(basename $0) prod localdev environment/prod/group_vars/containers/vault_cloudflare.yml environment/prod/group_vars/keymaster/vault_cloudflare.yml
  "
  exit 1
}

#Usage
if (( $# < 3 )); then
  usage
fi

#set -x



readonly currentEnv="$1"
readonly otherEnv="$2"

readonly currentSecretPath="$projectDir/vault-pass-${currentEnv}.secret"
readonly otherSecretPath="$projectDir/vault-pass-${otherEnv}.secret"

readonly specifiedEnv="$currentEnv"
source ./_vault.inc.bash

function otherVaultPath(){
  local currentPath="$1"
  echo "${currentPath/\/$currentEnv\//\/$otherEnv\//}"
}

## Assertions
assertYqInstalled
assertValidEnv "$currentEnv"
assertValidEnv "$otherEnv"
assertFilesExist "$currentSecretPath" "$otherSecretPath"
for vaultFilePath in "${@:3}"; do
  vaultFilePath="$(getFilePath "$vaultFilePath")"
  assertFileInEnv "$vaultFilePath" "$currentEnv"
  assertFilesExist "$vaultFilePath"
  assertFilesDoNotExist "$(otherVaultPath $vaultFilePath)"
done

# loop over file glob of files to rekey
for vaultFilePath in "${@:3}"; do
  # get abs path
  vaultFilePath="$(getFilePath "$vaultFilePath")"

  # generate the new filename by prefix with 'new_'
  otherVaultFilePath="$(otherVaultPath "$vaultFilePath")";
  echo "

  Starting to copy $vaultFilePath
  To file: $otherVaultFilePath
  "

  assertFilesExist "$vaultFilePath"

  if [[ -f $otherVaultFilePath ]]; then
    echo "Error - new file already exists at $otherVaultFilePath"
    exit 1
  fi

  mkdir -p "$(dirname $otherVaultFilePath)"

  # see https://stackoverflow.com/questions/43467180/how-to-decrypt-string-with-ansible-vault-2-3-0
  ## Process - using yq v4 syntax
  readarray params < <(yq eval 'keys | .[]' "$vaultFilePath")
  declare -a valuesDecrypted
  valuesDecrypted=()

  # loop over params and decrypt each value
  for param in "${params[@]}"; do
    # Trim whitespace from param
    param="${param%%[[:space:]]}"
    param="${param##[[:space:]]}"

    # Get the raw value for this param (yq v4 outputs vault strings correctly)
    vEnc=$(yq eval ".$param" "$vaultFilePath")

    if [[ $vEnc != *ANSIBLE_VAULT* ]]; then
      valuesDecrypted+=("$vEnc")
      continue
    fi

    # Decrypt the vault string - pass it directly to ansible-vault
    decrypted=$(echo "$vEnc" \
      | ansible-vault decrypt --vault-id="$currentEnv@$currentSecretPath" - \
      | grep -v 'Decryption successful')
    valuesDecrypted+=("$decrypted")
  done

  # Re-encrypt for the destination and write. Decrypted values are never printed and this
  # loop is never traced, so no secret reaches the terminal scrollback or a captured log.
  for i in "${!params[@]}"; do
    param="${params[$i]%%[[:space:]]}"
    secret="${valuesDecrypted[i]}"
    encrypted="$(printf '%s' "$secret" | ansible-vault encrypt_string \
      --vault-id="$otherEnv@$otherSecretPath" \
      --stdin-name "$param")"
    writeEncrypted "$encrypted" "$param" "$otherVaultFilePath"
  done

done

echo "

Completed successfully

"
