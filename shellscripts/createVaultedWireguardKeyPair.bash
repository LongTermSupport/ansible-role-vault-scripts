#!/usr/bin/env bash
# createVaultedWireguardKeyPair.bash — mint a WireGuard-compatible X25519 keypair and encrypt
# the PRIVATE half straight into an ansible-vault string, then optionally append it to a
# vault file. The private key is NEVER written to disk in the clear and NEVER printed — it
# exists only as base64 text held in shell variables and OS pipes between openssl and
# ansible-vault. The PUBLIC half is printed to stdout: WireGuard public keys are not secret,
# and callers typically keep them in a plain (unvaulted) file alongside the vaulted private
# halves — paste it there.
#
# No `wg` binary is required. WireGuard private/public keys are exactly raw 32-byte
# Curve25519 scalars, base64-encoded, with RFC7748/8410 clamping applied — bit-for-bit what
# `openssl genpkey -algorithm X25519` already produces, so any machine with openssl (which
# every machine running ansible-vault already has) can mint one.
#
# The sibling includes (_top.inc.bash / _vault.inc.bash) define projectDir, defaultEnv,
# finalSpecifiedEnv and vaultSecretsPath at runtime, and are resolved at runtime rather than
# lint time — hence the file-level shellcheck ignores for the sourced-include and
# sourced-variable checks.
# shellcheck disable=SC1091,SC2154
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
cd "$scriptDir" || exit 1
# Set up bash
source ./_top.inc.bash

function usage() {
  cat <<HELP

USAGE:

This script mints a WireGuard-compatible X25519 keypair. The PRIVATE half is encrypted into
an ansible-vault string and optionally appended to a vault file; the PUBLIC half is printed
to stdout for you to paste wherever this project keeps public keys.

Usage: ./$(basename "$0") [--replace] [varname] (optional: outputToFile) (optional: specifiedEnv - defaults to $defaultEnv)

--replace ROTATES an existing secret: the current definition of varname (its key line and
its whole indented !vault ciphertext block) is removed from outputToFile before the new one
is written, so the file ends up with exactly one definition. Without it, a varname that
already exists is a hard error — that stays the default so overwriting a live secret by
accident remains difficult.

Please note:
- The varname must be prefixed with 'vault_' and should name the PRIVATE key
  (e.g. vault_wg_green_private_key). This script does not mint or write a second variable
  for the public half — that value is not secret, and is printed for you to place yourself.
- If outputToFile contains an environment path (e.g. environment/prod/...), that
  environment is auto-detected and the specifiedEnv parameter can be omitted.
- If you specify both an environment in the path and the specifiedEnv parameter,
  they must match.

Examples:
  ./$(basename "$0") vault_wg_green_private_key environment/dc-proxmox/group_vars/all/vault_ssh_keys.yml
  ./$(basename "$0") --replace vault_wg_ctrlverify_private_key environment/dc-proxmox/group_vars/all/vault_ssh_keys.yml

HELP
  exit 1
}

# --replace makes ROTATION possible, mirroring createVaultedStringFromStdin.bash. Opt-in on
# purpose: overwriting a live secret by accident must stay difficult.
allowReplace=0
if [[ "${1:-}" == "--replace" ]]; then
  allowReplace=1
  shift
fi
readonly allowReplace

# Usage
if (($# < 1 || $# > 3)); then
  usage
fi

# Set variables
readonly varname="$1"
outputToFile="$(getProjectFilePathCreateIfNotExists "${2:-}")"
readonly userSpecifiedEnv="${3:-$defaultEnv}"

# Detect environment from output file path
readonly specifiedEnv="$userSpecifiedEnv"

# Source vault top
source ./_vault.inc.bash

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname"
readonly prefixed_varname="$varname"
validateOutputToFile "$outputToFile" "$varname" "$allowReplace"

if ! command -v openssl &>/dev/null; then
  error "openssl is required to mint a WireGuard keypair and was not found on PATH."
  exit 1
fi

# Generate straight to stdout (no `-out file` — the key is never written to disk in the
# clear) and base64-encode immediately: bash strings cannot safely hold NUL bytes, and
# command substitution silently truncates at the first one, so the raw DER bytes are never
# assigned to a variable — only base64 text is.
privDerB64="$(openssl genpkey -algorithm X25519 -outform DER 2>/dev/null | base64 -w0)"
if [[ -z "$privDerB64" ]]; then
  error "openssl failed to generate an X25519 keypair."
  exit 1
fi

# The last 32 bytes of a PKCS8 X25519 PrivateKeyInfo DER structure ARE the raw private
# scalar — the bytes before it are a fixed-length ASN.1 prefix, identical for every X25519
# key. Deriving the public half from THIS SAME material (rather than a second, independent
# generation) is what guarantees the two halves are actually a matching pair. Raw bytes stay
# inside pipes throughout; only their base64 form ever reaches a variable.
privKey="$(printf '%s' "$privDerB64" | base64 -d | tail -c 32 | base64 -w0)"
pubKey="$(printf '%s' "$privDerB64" | base64 -d | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | base64 -w0)"
unset privDerB64

if [[ -z "$privKey" || -z "$pubKey" ]]; then
  error "Failed to extract the raw key material from the generated keypair."
  exit 1
fi

# Create vault string. The private key is fed to ansible-vault on stdin, exactly as the
# stdin-sourced sibling script does, so it is never a command-line argument either.
encrypted="$(printf '%s' "$privKey" | ansible-vault encrypt_string \
  --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
  --stdin-name "$prefixed_varname")"
unset privKey

writeEncrypted "$encrypted" "$prefixed_varname" "$outputToFile"

printf '\nPublic key (NOT secret — paste this wherever this project keeps public keys):\n\n  %s\n\n' "$pubKey"
unset pubKey
