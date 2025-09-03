#!/bin/bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_allEnv.top.inc.bash

# Initialize summary counters
createdCount=0
skippedCount=0
failedCount=0
failedEnvs=()
skippedEnvs=()
createdEnvs=()

# Default flags
forceOverwrite=false
skipExisting=true
customEnvs=""
skipEnvs=""

function usage(){
  echo "
USAGE:

This script will generate unique SSH key pairs with no password protection for each environment.

You must only use these keys for read-only deploy keys (e.g., read-only access to GitHub repo for deployment).
You must never use an unprotected key for SSH access to servers.

Usage: ./$(basename $0) [OPTIONS] [varname_prefix] [email] [outputToFile with _env_ as env placeholder]

OPTIONS:
  --force                Force overwrite existing keys (default: false)
  --no-skip-existing     Fail if keys already exist (default: skip existing)
  --envs ENV1,ENV2       Only process specified environments (comma-separated)
  --skip-envs ENV1,ENV2  Skip specified environments (comma-separated)
  --help                 Show this help message

Please note:
- The varname_prefix must start with 'vault_'
- The outputToFile parameter must contain '_env_' as a placeholder for the environment name
- This script will replace '_env_' with each available environment name and call createVaultedSshDeployKeyPair.bash for each one
- Each environment gets a unique key pair (not the same key across environments)
- By default, existing keys are skipped without error
- Use --force to overwrite existing keys
- Use --no-skip-existing to get the original behavior (fail on existing keys)

Examples:
./$(basename $0) vault_github_deploy user@example.com environment/_env_/group_vars/containers/vault_github_deploy_keys.yml
./$(basename $0) --force vault_github_deploy user@example.com environment/_env_/group_vars/containers/vault_github_deploy_keys.yml
./$(basename $0) --envs dev,prod vault_github_deploy user@example.com environment/_env_/group_vars/containers/vault_github_deploy_keys.yml
./$(basename $0) --skip-envs untrusted vault_github_deploy user@example.com environment/_env_/group_vars/containers/vault_github_deploy_keys.yml

This will create a unique key pair in specified environments, replacing '_env_' with 'dev', 'prod', etc.
Each environment will have these variables:
vault_github_deploy
vault_github_deploy_pub
    "
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      forceOverwrite=true
      shift
      ;;
    --no-skip-existing)
      skipExisting=false
      shift
      ;;
    --envs)
      customEnvs="$2"
      shift 2
      ;;
    --skip-envs)
      skipEnvs="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Check remaining arguments
if (( $# != 3 )); then
    usage
    exit 1
fi

readonly varnamePrefix="$1"
readonly email="$2"
outputToFilePlaceholder="$3"
if [[ "$outputToFilePlaceholder" != "" ]]; then
  outputToFilePlaceholder="$(assertContainsPlaceholder "$outputToFilePlaceholder")"
  echo "outputToFilePlaceholder: $outputToFilePlaceholder"
fi

# Determine which environments to process
if [[ -n "$customEnvs" ]]; then
  # Convert comma-separated string to space-separated
  envsToProcess=$(echo "$customEnvs" | tr ',' ' ')
else
  envsToProcess="$allEnvNames"
fi

# Convert skip-envs comma-separated string to space-separated if provided
if [[ -n "$skipEnvs" ]]; then
  skipEnvsArray=$(echo "$skipEnvs" | tr ',' ' ')
else
  skipEnvsArray=""
fi

echo "Starting SSH deploy key generation..."
echo "Environments to process: $envsToProcess"
if [[ -n "$skipEnvsArray" ]]; then
  echo "Environments to skip: $skipEnvsArray"
fi
echo "Force overwrite: $forceOverwrite"
echo "Skip existing: $skipExisting"
echo ""

# Temporarily restore standard IFS for environment iteration since _top.inc.bash sets IFS=$'\n\t'
oldIFS="$IFS"
IFS="$standardIFS"

for envName in $envsToProcess; do
  # Check if this environment should be skipped
  skipThisEnv=false
  for skipEnv in $skipEnvsArray; do
    if [[ "$envName" == "$skipEnv" ]]; then
      skipThisEnv=true
      break
    fi
  done
  
  if [[ "$skipThisEnv" == "true" ]]; then
    echo "Skipping environment: $envName (explicitly excluded)"
    skippedEnvs+=("$envName")
    skippedCount=$((skippedCount + 1))
    continue
  fi
  
  if [[ "$outputToFilePlaceholder" != "" ]]; then
    outputToFile="${outputToFilePlaceholder/$placeholderEnvName/$envName}"
    # Convert to absolute path if relative (same logic as getProjectFilePathCreateIfNotExists but without creating)
    if [[ "$outputToFile" != "$projectDir"* ]]; then
      outputToFile="$projectDir/$outputToFile"
    fi
    # Get the real absolute path
    outputToFile="$(realpath -m "$outputToFile")"  # -m allows for non-existent files
  fi
  
  echo "Processing environment: $envName"
  echo "  DEBUG: outputToFile = '$outputToFile'"
  echo "  DEBUG: varnamePrefix = '$varnamePrefix'"
  
  # Check if keys already exist
  keyExists=false
  if [[ -f "$outputToFile" ]]; then
    echo "  Checking for existing keys in file..."
    if grep -q "^$varnamePrefix:" "$outputToFile" 2>/dev/null; then
      keyExists=true
      echo "  Found existing key: $varnamePrefix"
    else
      echo "  Key not found in vault file"
    fi
  else
    echo "  Vault file does not exist yet"
  fi
  
  if [[ "$keyExists" == "true" ]]; then
    if [[ "$forceOverwrite" == "true" ]]; then
      echo "  Keys exist but --force specified, will overwrite"
      # Remove existing keys from file
      sed -i "/^$varnamePrefix:/d" "$outputToFile"
      sed -i "/^${varnamePrefix}_pub:/d" "$outputToFile"
    elif [[ "$skipExisting" == "true" ]]; then
      echo "  Keys already exist, skipping (use --force to overwrite)"
      skippedEnvs+=("$envName")
      skippedCount=$((skippedCount + 1))
      continue
    fi
    # If skipExisting is false and not force, let createVaultedSshDeployKeyPair.bash handle the error
  fi
  
  # Call the individual script
  if ./createVaultedSshDeployKeyPair.bash "$varnamePrefix" "$email" "$outputToFile" "$envName"; then
    echo "  ✓ Successfully created keys for $envName"
    createdEnvs+=("$envName")
    createdCount=$((createdCount + 1))
  else
    echo "  ✗ Failed to create keys for $envName"
    failedEnvs+=("$envName")
    failedCount=$((failedCount + 1))
    # Continue processing other environments even if one fails
  fi
  echo ""
done

# Restore original IFS
IFS="$oldIFS"

# Print summary
echo "==========================================="
echo "SSH Deploy Key Generation Summary"
echo "==========================================="
echo "Total environments processed: $((createdCount + skippedCount + failedCount))"
echo "Successfully created: $createdCount"
echo "Skipped: $skippedCount"
echo "Failed: $failedCount"
echo ""

if [[ ${#createdEnvs[@]} -gt 0 ]]; then
  echo "Created in environments: ${createdEnvs[*]}"
fi

if [[ ${#skippedEnvs[@]} -gt 0 ]]; then
  echo "Skipped environments: ${skippedEnvs[*]}"
fi

if [[ ${#failedEnvs[@]} -gt 0 ]]; then
  echo "Failed environments: ${failedEnvs[*]}"
  echo ""
  echo "Note: Some environments failed. Check the output above for details."
  # Don't exit with error - we want to continue processing other environments
fi

echo ""

