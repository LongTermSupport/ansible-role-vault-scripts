#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash


# Usage
if (($# < 1 )); then
  echo "
  Usage:

  This script will dump all the secrets in the specifiedEnv

  $(basename $0) [specifiedEnv]

  "
  exit 1
fi

readonly specifiedEnv="$1"

cd "$projectDir"

ansible localhost \
  -m import_role \
  -a name=vault-scripts \
  --vault-id "${specifiedEnv}@vault-pass-"${specifiedEnv}.secret \
  -i "$projectDir/environment/$specifiedEnv" \
  --extra-vars env_dir="$projectDir/environment/$specifiedEnv"