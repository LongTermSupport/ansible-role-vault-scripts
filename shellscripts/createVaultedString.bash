#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash


function usage() {
  echo "
USAGE:

This script will encrypt the string you specify, then optionally add it to a vault file

If you are storing a password, consider using ./createVaultedPassword.bash instead
which will auto generate a long random password

Usage: ./$(basename $0) [options] [varname] [string] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

Options:
  --preserve-whitespace  Preserve leading and trailing whitespace in the string (default is to trim)

Please note:
- The varname must be prefixed with 'vault_'
- Leading and trailing whitespace is trimmed from the string by default
- If outputToFile contains an environment path (e.g., environment/prod/...), that environment will be 
  used automatically and the specifiedEnv parameter can be omitted
- If you specify both an environment in the path and the specifiedEnv parameter, they must match

Examples:
./$(basename $0) vault_github_token 'MySecretValue'
./$(basename $0) vault_api_key 'abc123xyz' environment/dev/group_vars/api/vault_keys.yml
./$(basename $0) --preserve-whitespace vault_multiline_text '  Text with whitespace  '
# Environment 'prod' is automatically detected from the path:
./$(basename $0) vault_cloudflare_token 'cf-token-123' environment/prod/group_vars/cloudflare/vault_tokens.yml

"
  exit 1
}

# Parse options
preserveWhitespace=false
params=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preserve-whitespace)
      preserveWhitespace=true
      shift
      ;;
    *)
      params+=("$1")
      shift
      ;;
  esac
done

# Check if we have enough parameters after option parsing
if (( ${#params[@]} < 2 || ${#params[@]} > 4 )); then
  usage
fi

readonly varname="${params[0]}"
string="${params[1]}"
outputToFile="$(getProjectFilePathCreateIfNotExists "${params[2]:-}")"
readonly userSpecifiedEnv="${params[3]:-$defaultEnv}"

# Trim whitespace unless --preserve-whitespace was specified
if [[ "$preserveWhitespace" == "false" ]]; then
  # Trim leading and trailing whitespace
  string="$(echo "$string" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  echo "Trimmed leading and trailing whitespace from string"
else
  echo "Preserving whitespace as requested"
fi

readonly string

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"

# Create vault string
encrypted="$(echo -n "$string" | ansible-vault encrypt_string \
  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"
