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
  ## Process



  readarray params < <(yq r $vaultFilePath --printMode p '*' -j)
  readarray valuesEncrypted < <(yq r $vaultFilePath --printMode v '*' -j)
  declare -a paramsDecrypted
  paramsDecrypted=()
  declare -a valuesDecrypted
  valuesDecrypted=()
  # loop over encrypted and build array of decrypted
  for vEncId in "${!valuesEncrypted[@]}"; do
    vEnc="${valuesEncrypted[$vEncId]}"
    if [[ $vEnc != *ANSIBLE_VAULT* ]];
    then
      continue
    fi
    vEnc="$(echo "$vEnc" | sed 's#\$ANSIBLE#ANSIBLE#g')"
    eval "vEncVal=$vEnc"
    valuesDecrypted+=("$(printf "%s$vEncVal" '$' \
      | ansible-vault decrypt  --vault-id="$specifiedEnv@$vaultSecretsPath" - \
      | grep -v 'Decryption successful' )")
    paramsDecrypted+=("${params[$vEncId]}")
  done
  for i in "${!valuesDecrypted[@]}"; do
    printf "\n\nParam: %s\nDecrypted:\n%s\n\n" "${paramsDecrypted[i]}" "${valuesDecrypted[$i]}"
  done

done
