#!/usr/bin/env bash
# browseSecrets.bash — explore and dump an environment's vaulted secrets without remembering
# their names or which file holds them.
#
#   browseSecrets.bash [specifiedEnv]                       interactive picker (fzf)
#   browseSecrets.bash --list [specifiedEnv]                every vaulted variable and its file
#   browseSecrets.bash --all [specifiedEnv]                 every secret decrypted, as one blob
#   browseSecrets.bash --get <name> [--file <path>] [env]   one secret, exactly, on stdout
#
# The picker lists every `<name>: !vault |` under environment/<env>/ (group_vars AND
# host_vars, at any depth) with a live decrypted preview. Enter on ONE row copies its value
# to the clipboard (wl-copy, xclip, xsel or pbcopy — whichever is installed; stdout carries
# only a notice, never the value). TAB-select several rows, or run with --all, and the
# selection is dumped as a blob: `=== name  (file)` then the value, one block per secret.
# `--get` accepts the name with or without its `vault_` prefix; a name that lives in more
# than one file must be pinned with --file.
#
# Environment overrides (tests and unusual desktops):
#   BROWSE_SECRETS_PICKER     the picker command, fed rows on stdin, expected to print the
#                             chosen rows (default: fzf --multi with the preview)
#   BROWSE_SECRETS_CLIPBOARD  the clipboard command fed the value on stdin; `none` disables
#                             (default: auto-detect)
#
# Nothing is written anywhere: values are decrypted to stdout or to the clipboard only.
#
# projectDir, defaultEnv, finalSpecifiedEnv, vaultSecretsPath and standardIFS come from the
# sourced includes, and specifiedEnv/noHeader are read BY them — resolved at runtime rather
# than lint time, hence the file-level shellcheck ignores for the sourced-include and
# referenced-but-not-assigned classes. SC2016 is awk's `$0`/`$2` inside single quotes.
# shellcheck disable=SC1091,SC2154,SC2034,SC2016
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
cd "$scriptDir" || exit 1
# No banner: stdout is the secret (or the blob) and must stay copy-paste clean.
noHeader=1
# Set up bash
source ./_top.inc.bash

usage() {
  cat <<USAGE >&2

  Usage

  $(basename "$0") [specifiedEnv]                       interactive picker (fzf)
  $(basename "$0") --list [specifiedEnv]                every vaulted variable and its file
  $(basename "$0") --all [specifiedEnv]                 every secret decrypted, as one blob
  $(basename "$0") --get <name> [--file <path>] [env]   one secret on stdout

  specifiedEnv defaults to $defaultEnv.

USAGE
  exit 1
}

mode="pick"
getName=""
pinFile=""
positional=()
while (( $# > 0 )); do
  case "$1" in
    --list) mode="list"; shift ;;
    --all) mode="all"; shift ;;
    --get)
      mode="get"
      [[ -n "${2:-}" && "${2:-}" != --* ]] || usage
      getName="$2"; shift 2 ;;
    --file)
      [[ -n "${2:-}" ]] || usage
      pinFile="$2"; shift 2 ;;
    -h|--help) usage ;;
    --*) error "unknown option $1"; usage ;;
    *) positional+=("$1"); shift ;;
  esac
done
(( ${#positional[@]} <= 1 )) || usage
readonly specifiedEnv="${positional[0]:-$defaultEnv}"
source ./_vault.inc.bash

readonly envDir="$projectDir/environment/$finalSpecifiedEnv"

# rows: every `<name>: !vault` at column 0 under the environment, as "name<TAB>relative-file".
listRows() {
  find "$envDir" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 \
    | sort -z \
    | xargs -0 awk -v root="$projectDir/" '
        match($0, /^[A-Za-z0-9_]+:[[:space:]]*!vault/) {
          name = $0; sub(/:.*/, "", name)
          file = FILENAME; sub("^" root, "", file)
          print name "\t" file
        }'
}

# decryptOne <name> <relative-file>: the value, exactly, on stdout. The vaulted block is the
# indented lines after the key; the plaintext never touches argv or disk.
decryptOne() {
  local name="$1" file="$projectDir/$2" errFile
  errFile="$(mktemp)"
  if ! awk -v n="$name" '
        $0 ~ "^" n ":" { g = 1; next }
        g && /^[[:space:]]/ { sub(/^[ \t]+/, ""); print; next }
        g { exit }' "$file" \
      | ansible-vault decrypt --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" --output=- - 2>"$errFile"; then
    error "could not decrypt $name from $2: $(cat "$errFile")"
    rm -f "$errFile"
    exitFromFunction
  fi
  rm -f "$errFile"
}

# dumpBlob: rows on stdin → the blob on stdout.
dumpBlob() {
  local name file
  while IFS=$'\t' read -r name file; do
    [[ -n "$name" ]] || continue
    printf '=== %s  (%s)\n' "$name" "$file"
    decryptOne "$name" "$file"
    printf '\n\n'
  done
}

# resolveRow <name> [pinFile]: the one row for a name (with or without vault_ prefix).
resolveRow() {
  local name="$1" pin="${2:-}" matches
  matches="$(listRows | awk -F'\t' -v n="$name" -v p="$pin" '
      ($1 == n || $1 == "vault_" n) && (p == "" || $2 == p)')"
  if [[ -z "$matches" ]]; then
    error "no vaulted variable named '$name' under environment/$finalSpecifiedEnv${pin:+ in $pin} (try --list)"
    exitFromFunction
  fi
  if (( $(printf '%s\n' "$matches" | wc -l) > 1 )); then
    error "'$name' is vaulted in more than one file — pin one with --file:
$(printf '%s\n' "$matches" | awk -F'\t' '{ print "    " $2 }')"
    exitFromFunction
  fi
  printf '%s\n' "$matches"
}

# clipboardCommand: the words of the clipboard command, or nothing when there is none.
clipboardCommand() {
  local configured="${BROWSE_SECRETS_CLIPBOARD:-}"
  if [[ "$configured" == "none" ]]; then
    return 0
  fi
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy > /dev/null; then printf 'wl-copy\n'; return 0; fi
  if [[ -n "${DISPLAY:-}" ]] && command -v xclip > /dev/null; then printf 'xclip -selection clipboard\n'; return 0; fi
  if [[ -n "${DISPLAY:-}" ]] && command -v xsel > /dev/null; then printf 'xsel --clipboard --input\n'; return 0; fi
  if command -v pbcopy > /dev/null; then printf 'pbcopy\n'; return 0; fi
  return 0
}

case "$mode" in
  list)
    listRows
    ;;
  all)
    listRows | dumpBlob
    ;;
  get)
    row="$(resolveRow "$getName" "$pinFile")"
    IFS=$'\t' read -r name file <<<"$row"
    decryptOne "$name" "$file"
    printf '\n'
    ;;
  pick)
    if [[ -n "${BROWSE_SECRETS_PICKER:-}" ]]; then
      IFS="$standardIFS" read -r -a picker <<<"$BROWSE_SECRETS_PICKER"
    else
      if ! command -v fzf > /dev/null; then
        error "fzf is not installed — install it, or use --list / --get / --all"
        exit 1
      fi
      # The preview re-enters this script for one row; {1}/{2} are the row's name and file.
      picker=(fzf --multi --delimiter $'\t' --with-nth "1,2"
        --header 'ENTER: copy one to the clipboard · TAB: select several, ENTER dumps them · ESC: quit'
        --preview "VAULT_SCRIPTS_PROJECT_DIR='$projectDir' '$scriptDir/browseSecrets.bash' --get {1} --file {2} '$finalSpecifiedEnv'"
        --preview-window 'down:40%:wrap')
    fi
    chosen="$(listRows | "${picker[@]}")" || { printf 'nothing chosen\n' >&2; exit 0; }
    [[ -n "$chosen" ]] || { printf 'nothing chosen\n' >&2; exit 0; }
    chosenCount="$(printf '%s\n' "$chosen" | wc -l)"
    clip="$(clipboardCommand)"
    if (( chosenCount == 1 )) && [[ -n "$clip" ]]; then
      IFS=$'\t' read -r name file <<<"$chosen"
      value="$(decryptOne "$name" "$file")"
      IFS="$standardIFS" read -r -a clipCmd <<<"$clip"
      printf '%s' "$value" | "${clipCmd[@]}"
      printf 'copied %s to the clipboard (%s characters) from %s\n' "$name" "${#value}" "$file"
      value=""
    else
      printf '%s\n' "$chosen" | dumpBlob
    fi
    ;;
esac
