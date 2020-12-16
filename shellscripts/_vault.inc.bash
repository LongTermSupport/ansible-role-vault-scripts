# Check if scriptDir has been defined
if [[ -z "$scriptDir" ]]; then
  # shellcheck disable=SC2016
  echo '
scriptDir has not been defined, this should be set using something like:

  readonly scriptDir=$(dirname $(readlink -f "$0"))

Exiting
  '
  exit 1
fi

#Bring in functions
source ./_vault.functions.inc.bash

# Basic sanity checks
if ! command -v ansible-vault &>/dev/null; then
  echo "Ansible has not been installed - please install ansible before running any of these scripts"
  exit 1
fi

ansibleVersionAtLeast "2.9.9"

readonly vaultSecretsPath="$scriptDir/../../vault-pass-${specifiedEnv}.secret"

readonly environmentPath="$scriptDir/../../environment/"

export environmentArray
readarray -t \
  environmentArray <<<"$(find "$environmentPath" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"

if [[ ! -f $vaultSecretsPath ]]; then
  echo "Vault Pass File not found at $vaultSecretsPath, you need to create this first"
  exit 1
fi


