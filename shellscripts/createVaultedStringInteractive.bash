#!/usr/bin/env bash
# createVaultedStringInteractive.bash — the fully interactive way to vault a secret a
# human is holding (a token copied from a dashboard, say). Every argument can be
# preset on the command line; anything not preset is asked for. The SECRET is always
# asked for on the terminal with echo off and is never an argument, so it never lands
# in argv, the process list, shell history or the terminal scrollback.
#
# It collects the answers, then hands the secret to createVaultedStringFromStdin.bash
# on a pipe, so validation, trimming, encryption and writing live in one place.
#
# The sibling includes (_top.inc.bash) define defaultEnv, projectDir and the error
# helper at runtime, and are resolved at runtime rather than lint time, hence the
# file-level disable below for the sourced-include and sourced-variable checks.
# shellcheck disable=SC1091,SC2154
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly scriptDir
cd "$scriptDir" || exit 1
# Set up bash
source ./_top.inc.bash

function usage() {
  cat <<HELP

USAGE:

This script asks for everything it needs and then vaults the secret you type. Anything
you preset on the command line is not asked for again. The secret itself is ALWAYS
prompted for, with echo off, and can never be passed as an argument.

Usage: ./$(basename "$0") [--replace] (optional: varname) (optional: outputToFile) (optional: specifiedEnv)

With no arguments it asks, in order: variable name, vault file, environment (only if
the file path does not already name one), whether to replace an existing variable, and
finally the secret.

--replace ROTATES an existing secret, exactly as in createVaultedStringFromStdin.bash.
Without it (and answering no when asked) an existing variable is a hard error.

Please note:
- The varname must be prefixed with 'vault_'
- A blank vault file means: do not write to a file, just print the encrypted string.
- Needs a real terminal on stdin; there is nothing to prompt on when input is piped.
  To vault a piped value use ./createVaultedStringFromStdin.bash.
- One line only. A terminal line holds at most about 4000 characters and cannot carry
  newlines, so multi-line secrets (PEM keys and the like) belong in
  ./createVaultedDataFromFile.bash instead.
- Surrounding whitespace is stripped before encryption. After you press Enter the
  script reports how many characters it read (never the value), so a failed paste is
  obvious.

Examples:
  ./$(basename "$0")
  ./$(basename "$0") vault_api_token environment/prod/group_vars/all/vault_tokens.yml
  ./$(basename "$0") --replace vault_api_token environment/prod/group_vars/all/vault_tokens.yml

HELP
  exit 1
}

# ask <target-var> <prompt> [default] — one visible line, default on a bare Enter.
function ask() {
  local -n _answer="$1"
  local _prompt="$2"
  local _default="${3:-}"
  local _suffix=""
  local _reply=""
  if [[ -n "$_default" ]]; then
    _suffix=" [$_default]"
  fi
  if ! read -r -p "${_prompt}${_suffix}: " _reply; then
    echo >&2
    error "End of input while answering '${_prompt}'. Nothing was vaulted."
    exit 1
  fi
  # _top.inc.bash narrows IFS to newline and tab, so read does not trim spaces itself.
  _reply="${_reply#"${_reply%%[![:space:]]*}"}"
  _reply="${_reply%"${_reply##*[![:space:]]}"}"
  _answer="${_reply:-$_default}"
}

# isKnownEnv <name> — true when <name> is one of the environments under the project.
function isKnownEnv() {
  local _env
  for _env in "${knownEnvs[@]}"; do
    if [[ "$_env" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

# --replace is optional and, once given, is never asked about.
replace="no"
replacePreset=0
if [[ "${1:-}" == "--replace" ]]; then
  replace="yes"
  replacePreset=1
  shift
fi

if (($# > 3)); then
  usage
fi

# Positional presets. A preset is "given" by position, so an empty string counts: it
# lets a caller say "no file" without being asked.
varname="${1:-}"
outputToFile="${2:-}"
specifiedEnv="${3:-}"
fileGiven=0
if (($# >= 2)); then
  fileGiven=1
fi
envGiven=0
if (($# >= 3)); then
  envGiven=1
fi

# Refuse to run without a terminal: there is nothing to prompt on.
if [[ ! -t 0 ]]; then
  error "No terminal on stdin, so there is nothing to prompt on. To vault a piped value use: <secret> | ./createVaultedStringFromStdin.bash <varname> ..."
  exit 1
fi

readarray -t knownEnvs < <(find "$projectDir/environment" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort)
# A local IFS, because [*] joins on the first character of IFS and _top.inc.bash sets it to a newline.
knownEnvsList="$(IFS=' '; echo "${knownEnvs[*]}")"

# 1. Variable name
while [[ ! "$varname" =~ ^vault_[a-z0-9_]+$ ]]; do
  if [[ -n "$varname" ]]; then
    echo "  '$varname' is not valid: it must start with 'vault_' and use lowercase letters, digits and underscores." >&2
  fi
  ask varname "Variable name (vault_...)"
done

# 2. Vault file
if ((fileGiven == 0)); then
  ask outputToFile "Vault file to write to, relative to the project, e.g. environment/prod/group_vars/all/vault_x.yml (blank = just print the encrypted string)"
fi

# 3. Environment: only asked for when the path does not already name one.
detectedEnv=""
if [[ "$outputToFile" =~ environment/([A-Za-z0-9_-]+)/ ]]; then
  detectedEnv="${BASH_REMATCH[1]}"
fi
if [[ -n "$detectedEnv" && -z "$specifiedEnv" ]]; then
  echo "  Environment '$detectedEnv' detected from the file path." >&2
  effectiveEnv="$detectedEnv"
else
  if ((envGiven == 0 && ${#specifiedEnv} == 0)); then
    ask specifiedEnv "Environment (${knownEnvsList})" "$defaultEnv"
  fi
  while ! isKnownEnv "$specifiedEnv"; do
    echo "  '$specifiedEnv' is not a known environment. Choose one of: ${knownEnvsList}" >&2
    ask specifiedEnv "Environment (${knownEnvsList})" "$defaultEnv"
  done
  effectiveEnv="$specifiedEnv"
fi

# 4. Replace an existing variable?
if ((replacePreset == 0)); then
  answer=""
  while [[ ! "$answer" =~ ^(y|yes|n|no)$ ]]; do
    ask answer "Replace the variable if it already exists? (y/n)" "n"
    answer="${answer,,}"
  done
  if [[ "$answer" == "y" || "$answer" == "yes" ]]; then
    replace="yes"
  fi
fi

# 5. Confirm what is about to happen, before asking for the secret.
{
  echo
  echo "About to vault:"
  echo "  variable:     $varname"
  echo "  vault file:   ${outputToFile:-(none, the encrypted string is printed)}"
  echo "  environment:  $effectiveEnv"
  echo "  replace:      $replace"
} >&2
proceed=""
while [[ ! "$proceed" =~ ^(y|yes|n|no)$ ]]; do
  ask proceed "Proceed and ask for the secret? (y/n)" "y"
  proceed="${proceed,,}"
done
if [[ "$proceed" == "n" || "$proceed" == "no" ]]; then
  error "Cancelled. Nothing was vaulted."
  exit 1
fi

# 6. The secret — always asked, echo off. -r keeps backslashes literal. A failed read
# means end of input (Ctrl-D) before a newline.
if ! read -r -s -p "Secret for $varname (input hidden): " secret; then
  echo >&2
  error "No secret entered (end of input before Enter). Nothing was vaulted."
  exit 1
fi
# -s suppressed the newline that Enter would have echoed.
echo >&2
echo "Read ${#secret} characters." >&2

# Build the stdin helper's arguments. The environment is passed only when the user
# chose one; when the path names it the helper detects it itself.
helperArgs=()
if [[ "$replace" == "yes" ]]; then
  helperArgs+=("--replace")
fi
helperArgs+=("$varname")
if [[ -n "$outputToFile" || -n "$specifiedEnv" ]]; then
  helperArgs+=("$outputToFile")
fi
if [[ -n "$specifiedEnv" ]]; then
  helperArgs+=("$specifiedEnv")
fi

# The value crosses to the helper on a pipe from a shell builtin, so it is never an
# argument to any process. The helper does the trimming, the empty check, the
# validation and the encryption.
printf '%s' "$secret" | ./createVaultedStringFromStdin.bash "${helperArgs[@]}"
