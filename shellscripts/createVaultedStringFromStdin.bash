#!/usr/bin/env bash
# createVaultedStringFromStdin.bash — encrypt a secret READ FROM STDIN into an
# ansible-vault !vault string, then optionally append it to a vault file. The
# secret is never a command-line argument, so it never lands in argv, the
# process list, shell history, or terminal output. This is the right script for
# piping a programmatically-obtained secret (e.g. `gh auth token`) into the vault
# without a human — or another tool — ever seeing the plaintext.
#
# The sibling includes (_top.inc.bash / _vault.inc.bash) define projectDir,
# defaultEnv, finalSpecifiedEnv and vaultSecretsPath at runtime, and are resolved
# at runtime rather than lint time — hence the file-level shellcheck ignores for
# the sourced-include and sourced-variable checks.
# shellcheck disable=SC1091,SC2154
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
cd "$scriptDir" || exit 1
# Set up bash
source ./_top.inc.bash

function usage() {
  cat <<HELP

USAGE:

This script encrypts a secret READ FROM STDIN, then optionally adds it to a
vault file. The secret is NEVER passed as a command-line argument, so it never
appears in the process list, shell history, or terminal output.

If you already have the plaintext on the command line, use ./createVaultedString.bash.
For a random password, use ./createVaultedPassword.bash.

Usage: <secret-on-stdin> | ./$(basename "$0") [varname] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

Please note:
- The varname must be prefixed with 'vault_'
- The secret comes from STDIN; surrounding whitespace and any trailing newline
  are stripped before encryption (a piped token followed by a newline is stored
  cleanly, without the newline).
- If outputToFile contains an environment path (e.g. environment/prod/...), that
  environment is auto-detected and the specifiedEnv parameter can be omitted.
- If you specify both an environment in the path and the specifiedEnv parameter,
  they must match.

Examples:
  gh auth token | ./$(basename "$0") vault_github_cve_token environment/dc-proxmox/group_vars/all/vault_github.yml
  printf %s "\$MY_SECRET" | ./$(basename "$0") vault_api_key environment/dev/group_vars/api/vault_keys.yml

HELP
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

# Refuse to hang on an interactive terminal: the secret MUST be piped in.
if [[ -t 0 ]]; then
  error "No secret on stdin. Pipe the secret in, e.g.: gh auth token | ./$(basename "$0") $varname ..."
  exit 1
fi

# Read the whole secret from stdin. Command substitution strips trailing
# newlines; the parameter expansions below strip any surrounding whitespace, so
# a piped value like a token followed by a newline is stored cleanly.
secret="$(cat)"
secret="${secret#"${secret%%[![:space:]]*}"}"
secret="${secret%"${secret##*[![:space:]]}"}"
readonly secret

if [[ -z "$secret" ]]; then
  error "The secret read from stdin is empty after trimming. Nothing to encrypt."
  exit 1
fi

# Detect environment from output file path
readonly specifiedEnv="$userSpecifiedEnv"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname"

# Create the vault string. The secret is fed to ansible-vault on stdin, exactly
# as the sibling scripts do, so it is never an argument here either.
encrypted="$(printf '%s' "$secret" | ansible-vault encrypt_string \
  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"
