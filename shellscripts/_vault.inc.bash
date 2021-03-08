#Bring in functions

# shellcheck source=./_top.inc.bash

# shellcheck source=./_vault.functions.inc.bash
source ./_vault.functions.inc.bash

# Basic sanity checks
if ! command -v ansible-vault &>/dev/null; then
  echo "Ansible has not been installed - please install ansible before running any of these scripts"
  exit 1
fi

ansibleVersionAtLeast "2.9.9"

readonly vaultSecretsPath="$projectDir/vault-pass-${specifiedEnv}.secret"

readonly environmentPath="$projectDir/environment/"

export environmentArray
readarray -t \
  environmentArray <<<"$(find "$environmentPath" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"

assertValidEnv "$specifiedEnv"

if [[ ! -f $vaultSecretsPath ]]; then
  echo "Vault Pass File not found at $vaultSecretsPath, you need to create this first"
  exit 1
fi


