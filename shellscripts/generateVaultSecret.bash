#!/usr/bin/env bash
readonly scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$scriptDir" || exit 1
# Set up bash
source ./_top.inc.bash

# Usage
if (($# < 1 )); then
  echo "
  Usage:

  This script will generate a vault secret file for the specifiedEnv

  $(basename $0) (optional: specifiedEnv - defaults to $defaultEnv) (optional: update pass a second param of 'update' to overwrite an existing vault secret)

  "
  exit 1
fi

readonly specifiedEnv="${1:-$defaultEnv}"

update=${2:-''}

readonly fileToCreate="$projectDir/vault-pass-${specifiedEnv}.secret"

if [[ -f "$fileToCreate" && "$update" != "update" ]]; then
  echo "

  Vault secret file already exists at $fileToCreate

  If you want to update an existing secrets file, for example to add a new env, please run:

  ./$(basename $0) $specifiedEnv update

  "
  exit 1
fi

touch "$fileToCreate"

# Source vault top
source ./_vault.inc.bash

generatePass() {
  openssl rand -base64 300 | tr -d '\n'
}

printf "%s %s\n" "$specifiedEnv" "$(generatePass)" >>"$vaultSecretsPath"
echo "Secret generated and added to $vaultSecretsPath"
