#!/usr/bin/env bash
readonly scriptDir=$(dirname "$(readlink -f "$0")")
cd "$scriptDir"
# Set up bash
source ./../_top.inc.bash
# Source vault top
source ./_vault.inc.bash

ansibleVersionAtLeast "2.10" "Storing multiple keys in a single file requires 2.10 minimum"

update=${1:-''}

if [[ -f "$vaultSecretsPath" && "$update" != "update" ]]; then
  echo "

  Vault secret file already exists at $vaultSecretsPath

  If you want to update an existing secrets file, for example to add a new env, please run:

  ./$(basename $0) update

  "
  exit 1
fi

generatePass() {
  openssl rand -base64 300 | tr -d '\n'
}

for ((e = 0; e < ${#environmentArray[@]}; e++)); do
  envName="${environmentArray[$e]}"
  printf "\n\n%s\n---------------------------\n" "$envName"
  if [[ "$(grep "$envName" "$vaultSecretsPath")" != "" ]]; then
    echo "Secret already defined, skipping"
    continue
  fi
  printf "%s %s\n" "$envName" "$(generatePass)" >>"$vaultSecretsPath"
  echo "Secret generated and added"
done
