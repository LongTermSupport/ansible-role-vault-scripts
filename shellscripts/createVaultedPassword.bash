#!/usr/bin/env bash
readonly scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$scriptDir" || exit 1
# Set up bash
source ./_top.inc.bash

# Usage
if (($# < 1 || $# > 3)); then
  echo "
  Usage:

  This script will generate a random password and encrypt it, then optionally add it to the file you specify

  Please note, the varname must be prefixed with 'vault_'

  $(basename $0) [varname] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)



  "
  exit 1
fi

# Set variables
readonly varname="$1"
readonly outputToFile="$(getProjectFilePathCreateIfNotExists "${2:-}")"
readonly specifiedEnv="${3:-$defaultEnv}"

readonly password='=+'"$(scriptDir/generatePassword.bash)"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"

# Create vault string
encrypted="$(echo -n "$password" | ansible-vault encrypt_string \
  --vault-id="$specifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"
