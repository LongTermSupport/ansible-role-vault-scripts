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

# --complete: the TAB helper behind the picker (names: vault_db_password, vault_api_key ×2 files,
# vault_host_token).
check "--complete: a single substring hit completes to the whole name" "vault_db_password" "$("$script" --complete pass dev)"
check "--complete: …case-insensitively" "vault_db_password" "$("$script" --complete PASS dev)"
check "--complete: an empty query completes to the common prefix of every name" "vault_" "$("$script" --complete '' dev)"
check "--complete: a prefix shared by several extends to their common prefix" "vault_" "$("$script" --complete va dev)"
check "--complete: a mid-name substring with nothing shared after it is left alone" "_" "$("$script" --complete _ dev)"
# The picker names now also include vault_host_token's sibling below, so "host_" has two
# continuations sharing "to": the query grows by exactly what they share.
"$roleScripts/createVaultedString.bash" vault_host_topic 'topic' environment/dev/host_vars/web3.yml dev > /dev/null
check "--complete: a mid-name substring extends by what every match shares after it" "host_to" "$("$script" --complete host_ dev)"
check "--complete: …and no further once the matches diverge" "host_to" "$("$script" --complete host_to dev)"
check "--complete: no hit leaves the query alone" "zzz" "$("$script" --complete zzz dev)"
check "--complete: the same name in two files is one candidate" "vault_api_key" "$("$script" --complete api dev)"

# --guides / --guide: a Markdown guide with {{ vault_… }} placeholders, printed with the values
# in place. Default location: environment/<env>/guides/<name>.md.
mkdir -p "$work/environment/dev/guides"
cat > "$work/environment/dev/guides/db-login.md" <<'GUIDE'
# Log in to the database

1. Connect as `app`.
2. Password: `{{ vault_db_password }}`
3. Token for the API: {{ vault_host_token }} (same as `{{vault_host_token}}`)
GUIDE
cat > "$work/environment/dev/guides/no-secrets.md" <<'GUIDE'
# Nothing vaulted here

Plain steps only.
GUIDE

out=$("$script" --guides dev)
check "--guides: lists every guide, name then title" "1" "$(grep -c -E '^db-login +Log in to the database$' <<<"$out")"
check "--guides: …including one with no placeholders" "1" "$(grep -c -E '^no-secrets +Nothing vaulted here$' <<<"$out")"

out=$("$script" --guide db-login dev)
check "--guide: every placeholder is replaced by the decrypted value" "1" "$(grep -c -F "2. Password: \`$secretValue\`" <<<"$out")"
check "--guide: the same placeholder twice on one line, with or without inner spaces, is replaced twice" "1" "$(grep -c -F "3. Token for the API: tok-two (same as \`tok-two\`)" <<<"$out")"
check "--guide: no placeholder survives" "0" "$(grep -c -F '{{' <<<"$out")"
check "--guide: the rest of the guide is untouched" "1" "$(grep -c -x '# Log in to the database' <<<"$out")"

out=$("$script" --guide no-secrets dev)
check "--guide: a guide with no placeholders is printed as-is" "1" "$(grep -c -x 'Plain steps only.' <<<"$out")"

# A multi-line value (a key) lands intact.
printf -- '-----BEGIN KEY-----\nline-one\nline-two\n-----END KEY-----' > "$work/key.txt"
touch "$work/environment/dev/group_vars/all/vault_key.yml"
"$roleScripts/createVaultedDataFromFile.bash" vault_ssh_key "$work/key.txt" environment/dev/group_vars/all/vault_key.yml dev > /dev/null
cat > "$work/environment/dev/guides/key.md" <<'GUIDE'
Save this as id_key:

{{ vault_ssh_key }}
GUIDE
out=$("$script" --guide key dev)
check "--guide: a multi-line value is substituted whole" "1" "$(grep -c -x 'line-two' <<<"$out")"
check "--guide: …with its first and last lines" "2" "$(grep -c -E '^-----(BEGIN|END) KEY-----$' <<<"$out")"

# A placeholder naming nothing vaulted: an error, and NOTHING on stdout.
cat > "$work/environment/dev/guides/broken.md" <<'GUIDE'
# Broken
Password: {{ vault_db_password }}
Missing: {{ vault_nonexistent }}
GUIDE
rc=0; out=$("$script" --guide broken dev 2>"$work/broken.err") || rc=$?
check "--guide: an unresolvable placeholder fails" "1" "$rc"
check "--guide: …naming the placeholder" "1" "$(grep -c 'vault_nonexistent' "$work/broken.err")"
check "--guide: …and prints nothing at all (no half-rendered guide)" "" "$out"

# A placeholder naming an ambiguous variable (vault_api_key lives in two files) fails too.
cat > "$work/environment/dev/guides/ambiguous.md" <<'GUIDE'
Key: {{ vault_api_key }}
GUIDE
rc=0; out=$("$script" --guide ambiguous dev 2>"$work/ambiguous.err") || rc=$?
check "--guide: an ambiguous placeholder fails" "1" "$rc"
check "--guide: …naming both files" "2" "$(grep -c -E 'vault_api.yml|web2.yml' "$work/ambiguous.err")"
check "--guide: …and prints nothing" "" "$out"

# --check: every placeholder resolves to exactly one vaulted variable, decided WITHOUT
# decrypting. Two proofs: a stand-in ansible-vault on PATH that records any call, and a second
# project root holding the same environment but no vault password file at all (a CI checkout).
fakeBin="$work/fakebin"
mkdir -p "$fakeBin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/vault-calls"\nexit 1\n' "$work" > "$fakeBin/ansible-vault"
chmod 0755 "$fakeBin/ansible-vault"
out=$(PATH="$fakeBin:$PATH" "$script" --guide db-login --check dev)
check "--guide --check: passes, counting the resolved placeholders" "1" "$(grep -c -E '^db-login: 2 placeholders resolve' <<<"$out")"
check "--guide --check: …without ever calling ansible-vault" "0" "$(if [[ -f "$work/vault-calls" ]]; then wc -l < "$work/vault-calls"; else echo 0; fi)"
noPass="$(mktemp -d)"
cp -r "$work/environment" "$noPass/environment"
printf '[defaults]\n' > "$noPass/ansible.cfg"
out=$(VAULT_SCRIPTS_PROJECT_DIR="$noPass" "$script" --guide db-login --check dev)
check "--guide --check: passes in a project root with no vault password file" "1" "$(grep -c -E '^db-login: 2 placeholders resolve' <<<"$out")"
out=$(VAULT_SCRIPTS_PROJECT_DIR="$noPass" "$script" --guides dev)
check "--guides: lists without a vault password file" "1" "$(grep -c -E '^db-login ' <<<"$out")"
out=$(VAULT_SCRIPTS_PROJECT_DIR="$noPass" "$script" --list dev)
check "--list: lists without a vault password file" "1" "$(grep -c -E '^vault_db_password ' <<<"$out")"
rm -rf "$noPass"
rc=0; out=$("$script" --guide broken --check dev 2>"$work/check.err") || rc=$?
check "--guide --check: fails on an unresolvable placeholder" "1" "$rc"
check "--guide --check: …naming it" "1" "$(grep -c 'vault_nonexistent' "$work/check.err")"
rc=0; out=$("$script" --guide ambiguous --check dev 2>"$work/check2.err") || rc=$?
check "--guide --check: fails on an ambiguous placeholder" "1" "$rc"
out=$("$script" --guide no-secrets --check dev)
check "--guide --check: a guide with no placeholders passes, saying so" "1" "$(grep -c -E '^no-secrets: 0 placeholders' <<<"$out")"

rc=0; err=$("$script" --guide nope dev 2>&1 >/dev/null) || rc=$?
check "--guide: an unknown guide fails" "1" "$rc"
check "--guide: …naming the directory it looked in" "1" "$(grep -c -F 'environment/dev/guides' <<<"$err")"

# VAULT_SCRIPTS_GUIDES_DIR relocates the directory; <env> in it is the environment name.
mkdir -p "$work/docs/guides/dev"
printf '# Elsewhere\n\n%s\n' 'Token: {{ vault_host_token }}' > "$work/docs/guides/dev/moved.md"
out=$(VAULT_SCRIPTS_GUIDES_DIR='docs/guides/<env>' "$script" --guides dev)
check "VAULT_SCRIPTS_GUIDES_DIR: --guides reads the relocated directory" "1" "$(grep -c -E '^moved +Elsewhere$' <<<"$out")"
check "VAULT_SCRIPTS_GUIDES_DIR: …and not the default one" "0" "$(grep -c 'db-login' <<<"$out")"
out=$(VAULT_SCRIPTS_GUIDES_DIR='docs/guides/<env>' "$script" --guide moved dev)
check "VAULT_SCRIPTS_GUIDES_DIR: --guide renders from there" "1" "$(grep -c -x 'Token: tok-two' <<<"$out")"

rc=0; err=$("$script" --guides --check dev 2>&1 >/dev/null) || rc=$?
check "--check without --guide is a usage error" "1" "$rc"

rc=0; err=$("$script" --get 2>&1 >/dev/null) || rc=$?
check "--get with no name is a usage error" "1" "$rc"

rc=0; err=$("$script" --list nope 2>&1 >/dev/null) || rc=$?
check "an unknown environment fails" "1" "$rc"

echo
printf 'passed: %s  failed: %s\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
