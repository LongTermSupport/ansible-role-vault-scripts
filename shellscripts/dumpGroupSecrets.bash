#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash


# Usage
if [[ "$*" == *-h* ]]; then
  echo "
  Usage:

  This script will dump all the secrets in the specifiedEnv

  $(basename $0) (optional: specifiedEnv - defaults to $defaultEnv) (optional: singleVariable to dump)

  "
  exit 1
fi

readonly specifiedEnv="${1:-$defaultEnv}"
readonly singleVariable="${2:-}"

readonly roleName="$(basename "$(dirname "$scriptDir")")"

cd "$projectDir"

if [[ "" != "$singleVariable" ]]; then
  echo "
Dumping Single Vaulted Variable: $singleVariable
" 1>&2
  ANSIBLE_STDOUT_CALLBACK=minimal ansible localhost \
  -m import_role \
  -a name="$roleName" \
  --vault-id "${specifiedEnv}@vault-pass-"${specifiedEnv}.secret \
  -i "$projectDir/environment/$specifiedEnv" \
  --extra-vars "env_dir='$projectDir/environment/$specifiedEnv' single_variable=$singleVariable" \
  | grep -oP '(?<=msg": ").*?(?=")' \
  | perl -pe 's/\\n/\n/g'
  echo
  exit 0
fi

echo "
Dumping All Vaulted Variables:
"
ansible localhost \
  -m import_role \
  -a name="$roleName" \
  --vault-id "${specifiedEnv}@vault-pass-"${specifiedEnv}.secret \
  -i "$projectDir/environment/$specifiedEnv" \
  --extra-vars env_dir="$projectDir/environment/$specifiedEnv"
echo
