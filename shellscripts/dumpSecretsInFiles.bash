#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

#Usage
if (( $# < 2 )); then
  echo "
  Usage

  $(basename $0) [specifiedEnv] [vaultFilePaths ...]

  "
  exit 1
fi

#set -x

readonly specifiedEnv="$1"
source ./_vault.inc.bash

assertYqInstalled


# loop over file glob of files to rekey
for vaultFilePath in "${@:2}"; do
  # get abs path
  vaultFilePath="$(getFilePath "$vaultFilePath")"

  echo "
########################################
Dumping Vault Secrets in $vaultFilePath
########################################
"

  assertFilesExist "$vaultFilePath"

  # see https://stackoverflow.com/questions/43467180/how-to-decrypt-string-with-ansible-vault-2-3-0
  ## Process - yq v4 syntax: list the top-level keys, then read each value raw
  readarray -t params < <(yq eval 'keys | .[]' "$vaultFilePath")
  declare -a paramsDecrypted
  paramsDecrypted=()
  declare -a valuesDecrypted
  valuesDecrypted=()
  # loop over params, decrypt every vaulted value
  for param in "${params[@]}"; do
    vEnc="$(yq eval ".[\"$param\"]" "$vaultFilePath")"
    if [[ $vEnc != *ANSIBLE_VAULT* ]];
    then
      continue
    fi
    valuesDecrypted+=("$(printf '%s\n' "$vEnc" \
      | ansible-vault decrypt  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" - \
      | grep -v 'Decryption successful' )")
    paramsDecrypted+=("$param")
  done
  for i in "${!valuesDecrypted[@]}"; do
    printf "\n\nParam: %s\nDecrypted:\n%s\n\n" "${paramsDecrypted[i]}" "${valuesDecrypted[$i]}"
  done

done
