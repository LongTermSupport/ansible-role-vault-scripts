#!/usr/bin/env bash
readonly scriptDir=$(dirname "$(readlink -f "$0")")
cd "$scriptDir"
# Set up bash
source ./../_top.inc.bash
# Source vault top
source ./_vault.functions.inc.bash

#Usage
if (( $# < 5 )); then
  echo "
  Usage

  $(basename $0) [currentKeyFilePath] [currentKeyFileID] [newKeyFilePath] [newKeyFileID] [vaultFilePaths ...]

  "
  exit 1
fi

#set -x

readonly currentKeyFilePath="$1"
readonly currentKeyFileID="$2"

readonly newKeyFilePath="$3"
readonly newKeyFileID="$4"

## Assertions
assertFilesExist "$currentKeyFilePath" "$newKeyFilePath"


for vaultFilePath in "${@:5}"; do

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

  if [[ ! -f /usr/bin/yq ]]; then
    sudo bash -c "wget https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"
  fi

  readarray params < <(yq r $vaultFilePath --printMode p '*' -j)
  readarray valuesEncrypted < <(yq r $vaultFilePath --printMode v '*' -j)
  declare -a valuesDecrypted
  valuesDecrypted=()

  # loop over encrypted and build array of decrypted
  for vEnc in "${valuesEncrypted[@]}"; do
    if [[ $vEnc != *ANSIBLE_VAULT* ]];
    then
      valuesDecrypted+=("$vEnc")
      continue
    fi
    vEnc="$(echo "$vEnc" | sed 's#\$ANSIBLE#ANSIBLE#g')"
    eval "vEncVal=$vEnc"
    valuesDecrypted+=("$(printf "%s$vEncVal" '$' \
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
