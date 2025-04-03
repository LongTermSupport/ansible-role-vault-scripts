#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage() {
  echo "
USAGE:

This script will generate a pre-shared key (hex string) and encrypt it, then optionally add it to a vault file

Usage: ./$(basename $0) [varname] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

Please note:
- The varname must be prefixed with 'vault_'
- If outputToFile contains an environment path (e.g., environment/prod/...), that environment will be 
  used automatically and the specifiedEnv parameter can be omitted
- If you specify both an environment in the path and the specifiedEnv parameter, they must match

Examples:
./$(basename $0) vault_zabbix_psk
./$(basename $0) vault_zabbix_psk environment/dev/group_vars/zabbixAgent/vault_zabbix_psk.yml
# Environment 'prod' is automatically detected from the path:
./$(basename $0) vault_zabbix_psk environment/prod/group_vars/zabbixAgent/vault_zabbix_psk.yml

"
  exit 1
}

# Usage
if (($# < 1 || $# > 3)); then
  usage
fi

# Set variables
readonly varname="$1"
outputToFile="$(getProjectFilePathCreateIfNotExists "${2:-}")"
readonly userSpecifiedEnv="${3:-$defaultEnv}"

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

psk="$(openssl rand -hex 32)"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"

# Create vault string
encrypted="$(echo -n "$psk" | ansible-vault encrypt_string \
  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"
