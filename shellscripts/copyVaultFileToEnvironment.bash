#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

#Usage
if (( $# < 3 )); then
  echo "

  This script will allow you to copy (and rekey) vault encrypted files between environments.

  Note - #THIS IS A BAD IDEA#
  Unless it is truly necessary. You should probably be using
  ./createPasswordsFromTemplate.bash

  Usage

  $(basename $0) [currentEnv] [newEnv] [vaultFilePaths ...]

  "
  exit 1
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
  ## Process
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
      | ansible-vault decrypt  --vault-id="$currentEnv@$currentSecretPath" - \
      | grep -v 'Decryption successful' )")
  done

  # Debug output
  echo "
  ##########################################################################
  Data Ready for Copying:
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
      --vault-id="$otherEnv@$otherSecretPath" \
      --stdin-name "$param")"
    set +x
    writeEncrypted "$encrypted" "$param" "$otherVaultFilePath"
  done

done

echo "

Completed successfully

"
