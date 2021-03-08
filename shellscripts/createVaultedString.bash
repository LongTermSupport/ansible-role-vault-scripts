#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir" || exit 1
# Set up bash
source ./_top.inc.bash


# Usage
if (($# < 1 || $# > 3)); then
  echo "
  Usage:

  This script will encrypt the string you specify , then optionally add it to the file you specify

  If you are storing a password, consider using ./createVaultedPassword.bash instead
  which will auto generate a long random password

  $(basename $0)  [varname] [string] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

  Please note, the varname must be prefixed with 'vault_'

  e.g

  ./$(basename $0) dev vault_github 'MySecretValue'

  "
  exit 1
fi

readonly varname="$1"
readonly string="$2"
readonly outputToFile="$(getFilePathOrEmptyString "${3:-}")"
readonly specifiedEnv="${4:-$defaultEnv}"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"

# Create vault string
encrypted="$(echo -n "$string" | ansible-vault encrypt_string \
  --vault-id="$specifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"
