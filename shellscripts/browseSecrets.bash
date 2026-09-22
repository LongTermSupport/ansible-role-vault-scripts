#!/usr/bin/env bash
# browseSecrets.bash — explore and dump an environment's vaulted secrets without remembering
# their names or which file holds them.
#
#   browseSecrets.bash [specifiedEnv]                       interactive picker (fzf)
#   browseSecrets.bash --list [specifiedEnv]                every vaulted variable and its file
#   browseSecrets.bash --all [specifiedEnv]                 every secret decrypted, as one blob
#   browseSecrets.bash --get <name> [--file <path>] [env]   one secret, exactly, on stdout
#   browseSecrets.bash --guides [specifiedEnv]              every guide the environment has
#   browseSecrets.bash --guide <name> [--check] [env]       a guide, its secrets filled in
#
# A GUIDE is a Markdown file the operator asks for by name — a whole procedure (a login, an
# onboarding, a recovery) written once, with `{{ vault_name }}` wherever a secret belongs.
# `--guide <name>` prints it with every placeholder replaced by that variable's decrypted
# value, so the procedure arrives in one human-readable piece instead of a document plus a
# separate fetch per secret. Every placeholder is resolved BEFORE anything is printed: a
# name that is not vaulted in the environment, or is vaulted in more than one file, is an
# error and stdout stays empty, never a half-rendered guide. `--check` resolves the
# placeholders without decrypting — no vault password needed, so a CI checkout can prove
# every guide's placeholders name real variables. Guides live in
# environment/<env>/guides/<name>.md; VAULT_SCRIPTS_GUIDES_DIR relocates that (a path
# relative to the project, or absolute, in which `<env>` stands for the environment name).
# `--guides` lists each guide's name and its first `# ` heading.
#
# The picker lists every `<name>: !vault |` under environment/<env>/ (group_vars AND
# host_vars, at any depth) with a live decrypted preview. Typing filters by plain substring
# (fzf --exact, not fuzzy per-character); TAB completes the query to the longest common
# prefix of the matching names, or to the one remaining match. Enter on ONE row copies its
# value to the clipboard (wl-copy, xclip, xsel or pbcopy — whichever is installed; stdout
# carries only a notice, never the value). CTRL-T-select several rows, or run with --all,
# and the selection is dumped as a blob: `=== name  (file)` then the value, one block per
# secret. `--get` accepts the name with or without its `vault_` prefix; a name that lives
# in more than one file must be pinned with --file. `--complete <query>` is the TAB
# helper: it prints the completed query and is what fzf's transform-query binding runs.
#
# Environment overrides (tests and unusual desktops):
#   BROWSE_SECRETS_PICKER     the picker command, fed rows on stdin, expected to print the
#                             chosen rows (default: fzf --multi with the preview)
#   BROWSE_SECRETS_CLIPBOARD  the clipboard command fed the value on stdin; `none` disables
#                             (default: auto-detect)
#   VAULT_SCRIPTS_GUIDES_DIR  where guides live; `<env>` is replaced by the environment
#                             (default: environment/<env>/guides)
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
  $(basename "$0") --complete <query> [specifiedEnv]    the query completed against the names
  $(basename "$0") --guides [specifiedEnv]              every guide the environment has
  $(basename "$0") --guide <name> [--check] [env]       a guide with its secrets filled in
                                                        (--check: prove the placeholders only)

  specifiedEnv defaults to $defaultEnv.

USAGE
  exit 1
}

mode="pick"
getName=""
pinFile=""
completeQuery=""
guideName=""
checkOnly=""
positional=()
while (( $# > 0 )); do
  case "$1" in
    --list) mode="list"; shift ;;
    --all) mode="all"; shift ;;
    --guides) mode="guides"; shift ;;
    --guide)
      mode="guide"
      [[ -n "${2:-}" && "${2:-}" != --* ]] || usage
      guideName="$2"; shift 2 ;;
    --check) checkOnly=1; shift ;;
    --get)
      mode="get"
      [[ -n "${2:-}" && "${2:-}" != --* ]] || usage
      getName="$2"; shift 2 ;;
    --file)
      [[ -n "${2:-}" ]] || usage
      pinFile="$2"; shift 2 ;;
    --complete)
      mode="complete"
      # An empty query is legitimate: TAB on an empty prompt completes to the common prefix.
      (( $# >= 2 )) || usage
      completeQuery="$2"; shift 2 ;;
    -h|--help) usage ;;
    --*) error "unknown option $1"; usage ;;
    *) positional+=("$1"); shift ;;
  esac
done
(( ${#positional[@]} <= 1 )) || usage
[[ -z "$checkOnly" || "$mode" == "guide" ]] || usage
readonly specifiedEnv="${positional[0]:-$defaultEnv}"

# The modes that only READ NAMES (--list, --guides, --complete, --guide --check) never touch
# the vault, so they do not go through _vault.inc.bash, which refuses to load without the
# vault password file. That is what lets a CI checkout — no password, by design — list an
# environment and prove every guide's placeholders. The environment discovery below is the
# same one _vault.inc.bash performs.
if [[ "$mode" == "list" || "$mode" == "guides" || "$mode" == "complete" || ( "$mode" == "guide" && -n "$checkOnly" ) ]]; then
  source ./_vault.functions.inc.bash
  readarray -t environmentArray <<<"$(find "$projectDir/environment/" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)"
  finalSpecifiedEnv="$specifiedEnv"
  assertValidEnv "$finalSpecifiedEnv"
else
  source ./_vault.inc.bash
fi

readonly envDir="$projectDir/environment/$finalSpecifiedEnv"

# guidesDir: where this environment's guides live (see VAULT_SCRIPTS_GUIDES_DIR above).
guidesDir() {
  local dir="${VAULT_SCRIPTS_GUIDES_DIR:-environment/<env>/guides}"
  dir="${dir//<env>/$finalSpecifiedEnv}"
  [[ "$dir" == /* ]] || dir="$projectDir/$dir"
  printf '%s\n' "$dir"
}

# guideTitle <file>: the first `# ` heading, or nothing.
guideTitle() {
  awk '/^# / { sub(/^# +/, ""); print; exit }' "$1"
}

# listGuides: every <name>.md in the guides directory as "name<TAB>title", sorted by name.
listGuides() {
  local dir file name
  dir="$(guidesDir)"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.md' -print0 | sort -z | while IFS= read -r -d '' file; do
    name="$(basename "$file" .md)"
    printf '%s\t%s\n' "$name" "$(guideTitle "$file")"
  done
}

# guideFile <name>: the guide's path, or an error naming where it was looked for.
guideFile() {
  local dir file
  dir="$(guidesDir)"
  file="$dir/$1.md"
  if [[ ! -f "$file" ]]; then
    error "no guide named '$1' in $dir (try --guides)"
    exitFromFunction
  fi
  printf '%s\n' "$file"
}

# guidePlaceholders <file>: every distinct name inside a `{{ … }}` placeholder, one per line.
guidePlaceholders() {
  awk '{
    line = $0
    while (match(line, /\{\{[[:space:]]*[A-Za-z0-9_]+[[:space:]]*\}\}/)) {
      ph = substr(line, RSTART + 2, RLENGTH - 4)
      gsub(/[[:space:]]/, "", ph)
      print ph
      line = substr(line, RSTART + RLENGTH)
    }
  }' "$1" | sort -u
}

# substitutePlaceholder <name>: stdin → stdout with every `{{ name }}` (any inner spacing)
# replaced by $VALUE. The value travels in the environment and is spliced by substr, never
# by a regex replacement, so a value holding `&`, `\` or newlines lands byte-for-byte.
substitutePlaceholder() {
  NAME="$1" awk '
    BEGIN { re = "\\{\\{[[:space:]]*" ENVIRON["NAME"] "[[:space:]]*\\}\\}" }
    {
      line = $0; out = ""
      while (match(line, re)) {
        out = out substr(line, 1, RSTART - 1) ENVIRON["VALUE"]
        line = substr(line, RSTART + RLENGTH)
      }
      print out line
    }'
}

# renderGuide <name>: resolve every placeholder first (a failure exits with nothing printed),
# then print the guide with the values in place. With checkOnly set, report the resolution
# and decrypt nothing.
renderGuide() {
  local file names name row varName varFile content
  local -a resolvedNames=() resolvedVars=() resolvedFiles=()
  file="$(guideFile "$1")"
  names="$(guidePlaceholders "$file")"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    row="$(resolveRow "$name")"
    IFS=$'\t' read -r varName varFile <<<"$row"
    resolvedNames+=("$name")
    resolvedVars+=("$varName")
    resolvedFiles+=("$varFile")
  done <<<"$names"
  if [[ -n "$checkOnly" ]]; then
    if (( ${#resolvedNames[@]} == 0 )); then
      printf '%s: 0 placeholders\n' "$1"
    else
      printf '%s: %d placeholders resolve to vaulted variables of environment/%s:\n' "$1" "${#resolvedNames[@]}" "$finalSpecifiedEnv"
      local i
      for i in "${!resolvedNames[@]}"; do
        printf '    %s  (%s)\n' "${resolvedNames[$i]}" "${resolvedFiles[$i]}"
      done
    fi
    return 0
  fi
  content="$(cat "$file")"
  local i value
  for i in "${!resolvedNames[@]}"; do
    value="$(decryptOne "${resolvedVars[$i]}" "${resolvedFiles[$i]}")"
    content="$(VALUE="$value" substitutePlaceholder "${resolvedNames[$i]}" <<<"$content")"
  done
  printf '%s\n' "$content"
}

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

# alignedRows: rows on stdin → "name<TAB>file<TAB>display" where display is the name padded
# to the widest name, then the file, so the two columns line up. Fields 1 and 2 stay exact.
alignedRows() {
  awk -F'\t' '
    { name[NR] = $1; file[NR] = $2; if (length($1) > w) w = length($1) }
    END { for (i = 1; i <= NR; i++) printf "%s\t%s\t%-*s  %s\n", name[i], file[i], w, name[i], file[i] }'
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
  while IFS=$'\t' read -r name file _; do
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

# completeQuery <query>: the query extended the way a shell's TAB would. Names containing
# the query (case-insensitive substring) are the candidates: one candidate completes to the
# whole name; several extend the query by whatever they all share immediately AFTER it
# (each name's tail from the query's first occurrence, longest common prefix of those);
# nothing shared, or no candidate, returns the query unchanged. Prints, never fails.
completeQuery() {
  local q="$1"
  listRows | cut -f1 | sort -u | awk -v q="$q" '
    BEGIN { lq = tolower(q) }
    { at = index(tolower($0), lq) } at == 0 { next }
    { n++; c[n] = substr($0, at); whole = $0 }
    END {
      if (n == 0) { print q; exit }
      if (n == 1) { print whole; exit }
      p = c[1]
      for (i = 2; i <= n; i++) {
        while (tolower(substr(c[i], 1, length(p))) != tolower(p)) p = substr(p, 1, length(p) - 1)
      }
      print (length(p) > length(q)) ? p : q
    }'
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
    listRows | alignedRows | cut -f3
    ;;
  all)
    listRows | dumpBlob
    ;;
  complete)
    completeQuery "$completeQuery"
    ;;
  guides)
    listGuides | alignedRows | cut -f3
    ;;
  guide)
    renderGuide "$guideName"
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
      # --exact: plain substring matching. TAB re-enters this script to complete the query;
      # multi-select therefore moves to CTRL-T. {q} is the current query.
      self="VAULT_SCRIPTS_PROJECT_DIR='$projectDir' '$scriptDir/browseSecrets.bash'"
      picker=(fzf --multi --exact --delimiter $'\t' --with-nth 3
        --header 'type to filter (substring) · TAB: complete · ENTER: copy one to the clipboard · CTRL-T: select several, ENTER dumps them · ESC: quit'
        --bind "tab:transform-query($self --complete {q} '$finalSpecifiedEnv')"
        --bind 'ctrl-t:toggle+down'
        --preview "$self --get {1} --file {2} '$finalSpecifiedEnv'"
        --preview-window 'down:40%:wrap')
    fi
    chosen="$(listRows | alignedRows | "${picker[@]}")" || { printf 'nothing chosen\n' >&2; exit 0; }
    [[ -n "$chosen" ]] || { printf 'nothing chosen\n' >&2; exit 0; }
    chosenCount="$(printf '%s\n' "$chosen" | wc -l)"
    clip="$(clipboardCommand)"
    if (( chosenCount == 1 )) && [[ -n "$clip" ]]; then
      IFS=$'\t' read -r name file _ <<<"$chosen"
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
