#!/usr/bin/env bash
set -euo pipefail
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
cd "$scriptDir" || exit 1
# NOTE: this is a thin wrapper — it does NOT source ./_top.inc.bash because it
# delegates the actual vault work to ./createVaultedString.bash (below), which
# performs the full setup (project root, vault-id selection, validation). Its own
# job is only to generate a correctly-sized signing key.

function usage() {
  echo "
USAGE:

Generate a cryptographically strong random SIGNING KEY (for HMAC-SHA / JWT
signing — HS256/HS384/HS512) and encrypt it into a vault file.

Why a dedicated script: ./createVaultedPassword.bash mints a ~47-char secret,
which is fine for a DB/user password but TOO SHORT for HS512, whose key must be
at least 64 bytes (lcobucci/jwt rejects a shorter key). Using the generic
password script for a JWT secret provisions a key the app refuses at boot (see
admin-api ADMIN_API_JWT_SECRET / Plan 00104). This script ALWAYS produces a key
long enough: 64 bytes of entropy by default => a 128-char hex key.

Usage: ./$(basename "$0") [--overwrite] [--bytes N] [varname] (optional: outputToFile) (optional: specifiedEnv - defaults to dev)

Options:
  --overwrite   Replace the variable if it already exists (passed through to
                createVaultedString.bash; FAILS if the variable does not exist).
  --bytes N     Random entropy bytes (default 64). The hex key is 2*N chars.
                Minimum 32 (=> a 64-char key, the HS512 floor); smaller is rejected.

Please note:
- The varname must be prefixed with 'vault_'
- If outputToFile contains an environment path (e.g. environment/prod/...), that
  environment is used automatically and specifiedEnv can be omitted.

Examples:
./$(basename "$0") vault_admin_api_jwt_secret environment/dev/group_vars/adminApi/vault_admin_api_jwt_secret.yml
./$(basename "$0") --overwrite vault_admin_api_jwt_secret environment/prod/group_vars/adminApi/vault_admin_api_jwt_secret.yml
"
  exit 1
}

# Parse options (mirrors createVaultedString.bash option style); leave the rest
# as positional params handed straight to createVaultedString.bash.
overwrite=""
entropyBytes=64
params=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overwrite) overwrite="--overwrite"; shift ;;
    --bytes) entropyBytes="${2:?--bytes needs a value}"; shift 2 ;;
    -h|--help) usage ;;
    *) params+=("$1"); shift ;;
  esac
done

# Usage: need at least a varname, at most varname + outputToFile + env.
if (( ${#params[@]} < 1 || ${#params[@]} > 3 )); then
  usage
fi

# FAIL FAST: entropy must yield a key of at least 64 chars (the HS512 floor).
if ! [[ "$entropyBytes" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --bytes must be a positive integer (got '$entropyBytes')" >&2
  exit 1
fi
if (( entropyBytes < 32 )); then
  echo "ERROR: --bytes $entropyBytes yields a $(( entropyBytes * 2 ))-char key; HS512 needs >= 64 chars. Use --bytes 32 or more (default 64)." >&2
  exit 1
fi

readonly varname="${params[0]}"
readonly outputToFile="${params[1]:-}"
readonly specifiedEnv="${params[2]:-}"

# Generate the signing key. Hex output is single-line, whitespace-free and has no
# shell-special characters, so it is safe to pass as an argument and renders into
# .env files without escaping. Length = 2 * entropyBytes (default 128 chars).
signingKey="$(openssl rand -hex "$entropyBytes")"

# Delegate encryption + vault write to the vetted createVaultedString.bash so the
# env-detection, vault-id selection, validation and (over)write logic is shared,
# not duplicated. Build the argument list so empty optional positionals are
# omitted (an explicit "" would be read as an invalid env by the child).
delegateArgs=()
if [[ -n "$overwrite" ]]; then
  delegateArgs+=("$overwrite")
fi
delegateArgs+=("$varname" "$signingKey")
if [[ -n "$outputToFile" ]]; then
  delegateArgs+=("$outputToFile")
fi
if [[ -n "$specifiedEnv" ]]; then
  delegateArgs+=("$specifiedEnv")
fi

exec ./createVaultedString.bash "${delegateArgs[@]}"
