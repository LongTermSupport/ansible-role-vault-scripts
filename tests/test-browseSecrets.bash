#!/usr/bin/env bash
# test-browseSecrets.bash — unit suite for shellscripts/browseSecrets.bash.
#
# Hermetic: a throwaway project root under mktemp (its own ansible.cfg, one environment
# named dev, a password file made by generateVaultSecret.bash, values written by
# createVaultedString.bash), pointed at through VAULT_SCRIPTS_PROJECT_DIR. Only the
# non-interactive modes are driven here: --list, --all, --get, and the fzf picker is
# exercised through FZF_DEFAULT_COMMAND-free plumbing by BROWSE_SECRETS_PICKER=cat, which
# stands in for fzf and "selects" every candidate. Nothing here touches a real vault.
set -euo pipefail
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
readonly roleScripts="${scriptDir}/../shellscripts"
readonly script="${roleScripts}/browseSecrets.bash"

for tool in ansible-vault yq; do
    if ! command -v "$tool" > /dev/null; then
        printf 'FAIL: %s is not installed — this suite cannot run\n' "$tool" >&2
        exit 1
    fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/environment/dev/group_vars/all" "$work/environment/dev/group_vars/web" "$work/environment/dev/host_vars"
printf '[defaults]\n' > "$work/ansible.cfg"
export VAULT_SCRIPTS_PROJECT_DIR="$work"
export noHeader=1

"$roleScripts/generateVaultSecret.bash" dev > /dev/null

# A value with characters that would trip a careless shell path.
secretValue="p4ss w0rd\$with\"quotes"
readonly secretValue
"$roleScripts/createVaultedString.bash" vault_db_password "$secretValue" environment/dev/group_vars/all/vault_db.yml dev > /dev/null
"$roleScripts/createVaultedString.bash" vault_api_key 'key-one' environment/dev/group_vars/web/vault_api.yml dev > /dev/null
"$roleScripts/createVaultedString.bash" vault_host_token 'tok-two' environment/dev/host_vars/web1.yml dev > /dev/null
printf 'plain_value: "not a secret"\n' >> "$work/environment/dev/group_vars/all/vault_db.yml"

passed=0
failed=0
check() {
    local label="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        passed=$((passed + 1)); printf '  PASS: %s\n' "$label"
    else
        failed=$((failed + 1)); printf '  FAIL: %s → %q (wanted %q)\n' "$label" "$got" "$want"
    fi
}

echo "=== browseSecrets.bash ==="

out=$("$script" --list dev)
check "--list: every vaulted variable across group_vars and host_vars, one per line" "3" "$(grep -c -E '^vault_(db_password|api_key|host_token)[[:space:]]' <<<"$out")"
check "--list: an unvaulted variable is not listed" "0" "$(grep -c 'plain_value' <<<"$out")"
check "--list: each row carries its file relative to the project" "1" "$(grep -c -E '^vault_host_token[[:space:]]+environment/dev/host_vars/web1.yml$' <<<"$out")"
check "--list: the file column is aligned (name padded to the widest name plus two spaces)" "1" "$(grep -c -E '^vault_api_key      environment/' <<<"$out")"
check "--list: …on every row" "1" "$(awk '{ c[index($0, "environment/")]++ } END { print length(c) }' <<<"$out")"

out=$("$script" --get vault_db_password dev)
check "--get: decrypts one value by name, exactly" "$secretValue" "$out"

out=$("$script" --get db_password dev)
check "--get: the vault_ prefix may be omitted" "$secretValue" "$out"

rc=0; err=$("$script" --get vault_missing dev 2>&1 >/dev/null) || rc=$?
check "--get: an unknown name fails" "1" "$rc"
check "--get: …and says so" "1" "$(grep -c 'no vaulted variable named' <<<"$err")"

rc=0; err=$("$script" --get plain_value dev 2>&1 >/dev/null) || rc=$?
check "--get: an unvaulted variable is refused, not printed" "1" "$rc"

"$roleScripts/createVaultedString.bash" vault_api_key 'key-dup' environment/dev/host_vars/web2.yml dev > /dev/null
rc=0; err=$("$script" --get vault_api_key dev 2>&1 >/dev/null) || rc=$?
check "--get: a name defined in two files fails" "1" "$rc"
check "--get: …naming both files" "2" "$(grep -c -E 'vault_api.yml|web2.yml' <<<"$err")"
out=$("$script" --get vault_api_key --file environment/dev/host_vars/web2.yml dev)
check "--get --file disambiguates" "key-dup" "$out"

out=$("$script" --all dev)
check "--all: dumps every secret as a blob, name then value" "4" "$(grep -c -E '^=== vault_' <<<"$out")"
check "--all: the blob carries the decrypted values" "1" "$(grep -c '^tok-two$' <<<"$out")"

# The picker path, with a stand-in for fzf that selects everything it is given.
out=$(BROWSE_SECRETS_PICKER=cat BROWSE_SECRETS_CLIPBOARD=none "$script" dev)
check "picker: a multi-selection is dumped as a blob" "4" "$(grep -c -E '^=== vault_' <<<"$out")"

# A stand-in that selects exactly one row, with no clipboard tool: printed, not copied.
out=$(BROWSE_SECRETS_PICKER='head -n1' BROWSE_SECRETS_CLIPBOARD=none "$script" dev)
check "picker: one selection with no clipboard prints the value" "1" "$(grep -c -E '^=== vault_' <<<"$out")"

# A stand-in clipboard: the value goes there, stdout carries only the notice.
clip="$work/clip.txt"
out=$(BROWSE_SECRETS_PICKER='head -n1' BROWSE_SECRETS_CLIPBOARD="dd status=none of=$clip" "$script" dev)
check "picker: one selection with a clipboard copies the exact value" "$secretValue" "$(cat "$clip")"
check "picker: …and prints no value, only the notice" "1" "$(grep -c -E '^copied vault_db_password to the clipboard \(21 characters\)' <<<"$out")"
check "picker: …the value is absent from stdout" "0" "$(grep -c -F 'p4ss w' <<<"$out")"

rc=0; err=$("$script" --get 2>&1 >/dev/null) || rc=$?
check "--get with no name is a usage error" "1" "$rc"

rc=0; err=$("$script" --list nope 2>&1 >/dev/null) || rc=$?
check "an unknown environment fails" "1" "$rc"

echo
printf 'passed: %s  failed: %s\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
