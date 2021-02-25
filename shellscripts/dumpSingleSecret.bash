#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash


# Usage
if (($# < 1 )); then
  echo "
  Usage:

  This script will dump all the secrets in the specifiedEnv, unless the
  singleVariable parameter is specified. In which case only the matching
  variable is printed.

  $(basename $0) specifiedEnv [singleVariable]

  "
  exit 1
fi

readonly specifiedEnv="$1"
readonly singleVariable="$2"

readonly roleName="$(basename "$(dirname "$scriptDir")")"

cd "$projectDir"

ANSIBLE_STDOUT_CALLBACK=minimal ansible localhost \
  -m import_role \
  -a name="$roleName" \
  --vault-id "${specifiedEnv}@vault-pass-"${specifiedEnv}.secret \
  -i "$projectDir/environment/$specifiedEnv" \
  --extra-vars "env_dir='$projectDir/environment/$specifiedEnv' single_variable=$singleVariable" \
  | grep -oP '(?<=msg": ").*?(?=")'
