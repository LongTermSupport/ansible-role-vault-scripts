#!/usr/bin/env bash
# test-createVaultedStringInteractive.bash — suite for shellscripts/createVaultedStringInteractive.bash.
#
# The script asks for every argument that was not preset, then ALWAYS prompts for the secret with
# echo off, and hands it to createVaultedStringFromStdin.bash on a pipe. It needs a real terminal on
# stdin, so the dialogue is driven through a pseudo-terminal by a small python3 helper that answers
# each prompt only once it has appeared (answering early races the terminal mode change).
#
# Hermetic: a throwaway project root under mktemp, pointed at through VAULT_SCRIPTS_PROJECT_DIR, with
# its own generated passphrase. Nothing here touches a real project or a real secret.
set -euo pipefail
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
readonly roleScripts="${scriptDir}/../shellscripts"
readonly interactive="${roleScripts}/createVaultedStringInteractive.bash"

for tool in ansible-vault yq python3; do
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

# Answers each prompt marker in order once it appears on the terminal. Writes what the script
# printed to $1, whatever the terminal echoed back to $2, and prints the exit code.
driver="$work/pty-dialogue.py"
cat > "$driver" <<'PYEOF'
import os
import pty
import subprocess
import sys
import threading
import time

script, outfile, echofile, *rest = sys.argv[1:]
sep = rest.index("--")
args, steps = rest[:sep], rest[sep + 1:]
pairs = list(zip(steps[0::2], steps[1::2]))

master, slave = pty.openpty()
proc = subprocess.Popen([script, *args], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
os.close(slave)
fd = proc.stdout.fileno()
chunks = []


def pump():
    while True:
        data = os.read(fd, 4096)
        if not data:
            return
        chunks.append(data)


reader = threading.Thread(target=pump, daemon=True)
reader.start()
pos = 0
for marker, reply in pairs:
    deadline = time.monotonic() + 30
    found = False
    while proc.poll() is None and time.monotonic() < deadline:
        text = b"".join(chunks).decode(errors="replace")
        idx = text.find(marker, pos)
        if idx >= 0:
            pos = idx + len(marker)
            found = True
            break
        time.sleep(0.05)
    if not found or proc.poll() is not None:
        break
    os.write(master, reply.encode() + b"\n")
code = proc.wait(timeout=60)
reader.join(timeout=5)
os.set_blocking(master, False)
echoed = b""
while True:
    try:
        piece = os.read(master, 4096)
    except (BlockingIOError, OSError):
        break
    if not piece:
        break
    echoed += piece
os.close(master)
open(outfile, "w").write(b"".join(chunks).decode(errors="replace"))
open(echofile, "w").write(echoed.decode(errors="replace"))
print(code)
PYEOF

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
    [[ -f $2 ]] || { echo 0; return; }
    awk -v re="$1" '$0 ~ re { n++ } END { print n + 0 }' "$2"
}

# Count lines containing a fixed string. A file that does not exist contains nothing.
countFixed() {
    [[ -f $2 ]] || { echo 0; return; }
    awk -v s="$1" 'index($0, s) { n++ } END { print n + 0 }' "$2"
}

out="$work/out.txt"
echoed="$work/echoed.txt"
# dialogue <args...> -- <marker reply>...   → sets $code; output in $out, terminal echo in $echoed
dialogue() {
    code=$(python3 "$driver" "$interactive" "$out" "$echoed" "$@")
}

secret="interactive-test-value-Zq7Lm2Xv9Rt4"
rel="environment/dev/group_vars/all/vault_dialogue.yml"
file="$work/$rel"

echo "=== createVaultedStringInteractive ==="

if printf '%s\n' "$secret" | "$interactive" vault_zz "$rel" > "$out" 2>&1; then rc=0; else rc=$?; fi
check "refuses when stdin is not a terminal" "1" "$rc"
check "…and points at the stdin helper" "1" "$(countFixed 'createVaultedStringFromStdin.bash' "$out")"
check "…and creates nothing" "no" "$([[ -e $file ]] && echo yes || echo no)"

if "$interactive" a b c d > "$out" 2>&1 < /dev/null; then rc=0; else rc=$?; fi
check "too many arguments shows usage" "1" "$rc"

# No arguments: asks everything; the file path names the environment, so it is not asked.
dialogue -- "Variable name" vault_zz "Vault file to write to" "$rel" \
    "Replace the variable" n "Proceed and ask" y "input hidden" "$secret"
check "a full dialogue succeeds" "0" "$code"
check "…writes the variable as a !vault block" "1" "$(countMatching '^vault_zz: !vault \|$' "$file")"
check "…the environment is detected, not asked" "0" "$(countFixed 'Environment (' "$out")"
check "…the plaintext is not in the vault file" "0" "$(countFixed "$secret" "$file")"
check "…the plaintext is not printed" "0" "$(countFixed "$secret" "$out")"
check "…the terminal never echoed the secret" "0" "$(countFixed "$secret" "$echoed")"
check "…and it reports how many characters were read" "1" "$(countFixed "${#secret} characters" "$out")"

# Presets are not asked again; an existing variable is refused unless replacing.
dialogue vault_zz "$rel" -- "Replace the variable" n "Proceed and ask" y "input hidden" "${secret}-changed"
check "an existing variable is refused when not replacing" "1" "$code"
check "…presets are not asked for again" "0" "$(countFixed 'Variable name' "$out")"

dialogue --replace vault_zz "$rel" -- "Proceed and ask" y "input hidden" "${secret}-rotated"
check "--replace rotates the variable" "0" "$code"
check "…leaving exactly one definition" "1" "$(countMatching '^vault_zz: !vault \|$' "$file")"
check "…and never asks about replacing" "0" "$(countFixed 'Replace the variable' "$out")"

# A blank vault file prints the ciphertext instead, and then the environment is asked.
rm -f "$file"
dialogue vault_zz -- "Vault file to write to" "" "Environment (" "  dev " \
    "Replace the variable" n "Proceed and ask" y "input hidden" "$secret"
check "a blank vault file asks for the environment and succeeds" "0" "$code"
check "…printing the ciphertext" "1" "$(countFixed 'ANSIBLE_VAULT;' "$out")"
check "…and writing no file" "no" "$([[ -e $file ]] && echo yes || echo no)"

# An invalid variable name is asked for again.
dialogue -- "Variable name" BadName "Variable name" vault_zz "Vault file to write to" "$rel" \
    "Replace the variable" n "Proceed and ask" y "input hidden" "$secret"
check "an invalid variable name is re-asked, then accepted" "0" "$code"
check "…with an explanation" "1" "$(countFixed 'is not valid' "$out")"

# Declining at the summary cancels before the secret is ever asked for.
rm -f "$file"
dialogue vault_zz "$rel" -- "Replace the variable" n "Proceed and ask" n
check "declining at the summary cancels" "1" "$code"
check "…without ever asking for the secret" "0" "$(countFixed 'input hidden' "$out")"
check "…and writes nothing" "0" "$(countFixed 'vault_zz' "$file")"

# An empty secret is rejected by the stdin helper and nothing is recorded.
dialogue vault_zz "$rel" -- "Replace the variable" n "Proceed and ask" y "input hidden" ""
check "an empty secret is rejected" "1" "$code"
check "…and no variable is written" "0" "$(countFixed 'vault_zz' "$file")"

printf 'passed: %s  failed: %s\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
