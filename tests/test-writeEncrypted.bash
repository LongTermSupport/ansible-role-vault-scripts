#!/usr/bin/env bash
# test-writeEncrypted.bash — unit suite for writeEncrypted in shellscripts/_vault.functions.inc.bash.
#
# A vault file the scripts create must be a YAML document that opens with `---`: yamllint and
# ansible-lint both reject a file without the document start. The create scripts resolve their
# output path through getProjectFilePathCreateIfNotExists, which `touch`es it, so a brand-new
# file already exists (empty) by the time writeEncrypted runs — that is the case driven here.
#
# Hermetic: a throwaway project root under mktemp, pointed at through VAULT_SCRIPTS_PROJECT_DIR.
set -euo pipefail
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
readonly roleScripts="${scriptDir}/../shellscripts"

for tool in ansible-vault yq; do
    if ! command -v "$tool" > /dev/null; then
        printf 'FAIL: %s is not installed — this suite cannot run\n' "$tool" >&2
        exit 1
    fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/environment/dev/group_vars/all"
printf '[defaults]\n' > "$work/ansible.cfg"
export VAULT_SCRIPTS_PROJECT_DIR="$work"
export noHeader=1

"$roleScripts/generateVaultSecret.bash" dev > /dev/null

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

# Count lines matching an ERE; awk rather than `grep -c`, which exits 1 on a zero count.
countMatching() {
    awk -v re="$1" '$0 ~ re { n++ } END { print n + 0 }' "$2"
}

echo "=== writeEncrypted ==="

newFile="$work/environment/dev/group_vars/all/vault_new.yml"
"$roleScripts/createVaultedString.bash" vault_first 'one' environment/dev/group_vars/all/vault_new.yml dev > /dev/null
check "a new file opens with the YAML document start" "---" "$(awk 'NR==1' "$newFile")"
check "…and carries the creation header" "1" "$(countMatching '^# Vault File Created with createVaultedString.bash at ' "$newFile")"
check "…and has no trailing whitespace on any line" "0" "$(countMatching '[[:space:]]$' "$newFile")"

"$roleScripts/createVaultedString.bash" vault_second 'two' environment/dev/group_vars/all/vault_new.yml dev > /dev/null
check "appending to an existing file adds no second document start" "1" "$(countMatching '^---$' "$newFile")"
check "…and the file still parses to both keys" "vault_first vault_second" "$(yq eval 'keys | join(" ")' "$newFile")"

existingFile="$work/environment/dev/group_vars/all/vault_existing.yml"
printf 'plain_value: "kept"\n' > "$existingFile"
"$roleScripts/createVaultedString.bash" vault_third 'three' environment/dev/group_vars/all/vault_existing.yml dev > /dev/null
check "a pre-existing non-empty file is appended to, not given a header" "plain_value: \"kept\"" "$(awk 'NR==1' "$existingFile")"
check "…and gains no document start" "0" "$(countMatching '^---$' "$existingFile")"

printf 'passed: %s  failed: %s\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
