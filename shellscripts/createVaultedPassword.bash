#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

# Usage
if (($# < 2 || $# > 3)); then
  echo "
  Usage:

  This script will generate a random password and encrypt it, then optionally add it to the file you specify

  $(basename $0) [specifiedEnv] [varname] (optional: outputToFile)

  "
  exit 1
fi

# Set variables
readonly specifiedEnv="$1"
readonly varname="$2"
readonly outputToFile="$(getProjectFilePathCreateIfNotExists "${3:-}")"
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
