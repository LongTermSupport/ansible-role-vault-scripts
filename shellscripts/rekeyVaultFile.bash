#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

#Usage
if (( $# < 5 )); then
  echo "
  Usage

  $(basename $0) [currentKeyFileID] [currentKeyFilePath] [newKeyFileID] [newKeyFilePath] [vaultFilePaths ...]

  "
  exit 1
fi

#set -x



readonly currentKeyFileID="$1"
currentKeyFilePath="$(getFilePath "$2")"

readonly newKeyFileID="$3"
newKeyFilePath="$(getFilePath "$4")"

readonly specifiedEnv="$currentKeyFileID"
source ./_vault.inc.bash

## Assertions
assertYqInstalled
assertFilesExist "$currentKeyFilePath" "$newKeyFilePath"

# loop over file glob of files to rekey
for vaultFilePath in "${@:5}"; do
  # get abs path
  vaultFilePath="$(getFilePath "$vaultFilePath")"

  # generate the new filename by prefix with 'new_'
  newVaultFilePath="$(dirname "$vaultFilePath")/new_$( basename "$vaultFilePath")";
  echo "

  Starting to rekey $vaultFilePath
  New file: $newVaultFilePath
  "

  assertFilesExist "$vaultFilePath"

  if [[ -f $newVaultFilePath ]]; then
    echo "Error - new file already exists at $newVaultFilePath"
    exit 1
  fi

  # see https://stackoverflow.com/questions/43467180/how-to-decrypt-string-with-ansible-vault-2-3-0
  ## Process

  ## Process - yq v4 syntax: list the top-level keys, then read each value raw
  readarray -t params < <(yq eval 'keys | .[]' "$vaultFilePath")
  declare -a valuesDecrypted
  valuesDecrypted=()

  # loop over params and build array of decrypted
  for param in "${params[@]}"; do
    vEnc="$(yq eval ".[\"$param\"]" "$vaultFilePath")"
    if [[ $vEnc != *ANSIBLE_VAULT* ]];
    then
      valuesDecrypted+=("$vEnc")
      continue
    fi
    valuesDecrypted+=("$(printf '%s\n' "$vEnc" \
      | ansible-vault decrypt  --vault-id="$currentKeyFileID@$currentKeyFilePath" - \
      | grep -v 'Decryption successful' )")
  done

  # Debug output
  echo "
  ##########################################################################
  Data Ready for Rekeying:
  ##########################################################################
  "
  for i in "${!params[@]}"; do
    printf "\n\nParam: %s\nDecrypted:\n%s\n\n" "${params[i]}" "${valuesDecrypted[$i]}"
  done

  # loop over params and write encrypted to new file
  for i in "${!params[@]}"; do
    set -x
    param="${params[$i]%%[[:space:]]}"
    secret="${valuesDecrypted[i]}"
    encrypted="$(echo -n "$secret" | ansible-vault encrypt_string \
      --vault-id="$newKeyFileID@$newKeyFilePath" \
      --stdin-name "$param")"
    set +x
    writeEncrypted "$encrypted" "$param" "$newVaultFilePath"
  done

done
