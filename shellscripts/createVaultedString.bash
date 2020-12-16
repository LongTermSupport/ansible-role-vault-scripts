#!/usr/bin/env bash
readonly scriptDir=$(dirname "$(readlink -f "$0")")
cd "$scriptDir"
# Set up bash
source ./../_top.inc.bash


# Usage
if (($# < 1 || $# > 3)); then
  echo "
  Usage:

  This script will encrypt the string you specify , then optionally add it to the file you specify

  $(basename $0) [specifiedEnv] [varname] [string] (optional: outputToFile)

  "
  exit 1
fi

readonly specifiedEnv="$1"
readonly varname="$2"
readonly string="$3"
readonly outputToFile="${4:-}"

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
