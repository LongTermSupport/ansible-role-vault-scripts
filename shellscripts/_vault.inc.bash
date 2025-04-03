#Bring in functions
source ./_vault.functions.inc.bash

# Basic sanity checks
if ! command -v ansible-vault &>/dev/null; then
  echo "Ansible has not been installed - please install ansible before running any of these scripts"
  exit 1
fi

ansibleVersionAtLeast "2.9.9"

readonly environmentPath="$projectDir/environment/"

export environmentArray
readarray -t \
  environmentArray <<<"$(find "$environmentPath" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"

# If outputToFile is defined, check for environment in the path
if [[ -n "${outputToFile:-}" ]]; then
  # Capture output in a variable
  finalSpecifiedEnv="$(detectEnvironmentFromPath "$outputToFile" "$specifiedEnv")"
  # Ensure we got a clean value (just the environment name)
  if [[ ! "$finalSpecifiedEnv" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    # If there was extra output, try to extract just the last line
    finalSpecifiedEnv="$(echo "$finalSpecifiedEnv" | tail -n1)"
  fi
else
  finalSpecifiedEnv="$specifiedEnv"
fi

assertValidEnv "$finalSpecifiedEnv"

readonly vaultSecretsPath="$projectDir/vault-pass-${finalSpecifiedEnv}.secret"

if [[ ! -f $vaultSecretsPath ]]; then
  echo "Vault Pass File not found at $vaultSecretsPath, you need to create this first"
  exit 1
fi


