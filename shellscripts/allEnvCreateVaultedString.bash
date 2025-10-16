#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

function usage(){
  echo "
USAGE:

This script will encrypt the same string for each environment and add it to environment-specific files.

Usage: ./$(basename $0) [options] [varname] [string] [outputToFile with _env_ as env placeholder]

Options:
  --preserve-whitespace  Preserve leading and trailing whitespace in the string (default is to trim)

Please note:
- The varname must start with 'vault_'
- Leading and trailing whitespace is trimmed from the string by default
- The outputToFile parameter must contain '_env_' as a placeholder for the environment name
- This script will replace '_env_' with each available environment name and call createVaultedString.bash for each one

Examples:
./$(basename $0) vault_api_key 'my-secret-api-key' environment/_env_/group_vars/api/vault_keys.yml
./$(basename $0) --preserve-whitespace vault_multiline_text '  Text with whitespace  ' environment/_env_/group_vars/api/vault_text.yml

This will encrypt the same string in every environment, replacing '_env_' with 'dev', 'prod', etc.
    "
}

# Parse options
preserveWhitespace=""
params=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preserve-whitespace)
      preserveWhitespace="--preserve-whitespace"
      shift
      ;;
    *)
      params+=("$1")
      shift
      ;;
  esac
done

# Check if we have enough parameters after option parsing
if (( ${#params[@]} < 3 )); then
  usage
  exit 1
fi

readonly varname="${params[0]}"
readonly string="${params[1]}"
outputToFilePlaceholder="${params[2]}"

if [[ "$outputToFilePlaceholder" != "" ]]; then
  outputToFilePlaceholder="$(assertContainsPlaceholder "$outputToFilePlaceholder")"
  echo "outputToFilePlaceholder: $outputToFilePlaceholder"
fi

# Temporarily restore standard IFS for proper word splitting in the loop
IFS="$standardIFS"
for envName in $allEnvNames; do
  if [[ "$outputToFilePlaceholder" != "" ]]; then
    outputToFile="${outputToFilePlaceholder/$placeholderEnvName/$envName}"
  fi
  if [[ -n "$preserveWhitespace" ]]; then
    ./createVaultedString.bash $preserveWhitespace "$varname" "$string" "$outputToFile" "$envName"
  else
    ./createVaultedString.bash "$varname" "$string" "$outputToFile" "$envName"
  fi
done
# Restore vault scripts IFS
IFS=$'\n\t'