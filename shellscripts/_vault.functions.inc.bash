

# environmentArray and defaultEnv are defined by the _top.inc.bash / _vault.inc.bash files
# that source this one, so they are not assigned here. They are referenced with `:-` defaults
# rather than silenced with a directive: an unset environmentArray then fails the comparison
# and reports a clear error, instead of expanding to nothing and matching every env.
function assertValidEnv(){
  local _env="$1"
  if [[ "${environmentArray[*]:-}" == *"${_env}"* ]]; then
    return 0
  fi
  error "Error, specified env $_env is not found in ${environmentArray[*]:-<unset>}"
  exitFromFunction
}

function assertPrefixedWithVault(){
  local _varname="$1"
  if [[ "$_varname" != vault_* ]];
  then
    error "Error, $_varname is not prefixed with 'vault_'"
    error "You must prefix all encrypted string variables with 'vault_'"
    exit 1
  fi
  echo "$_varname"
}

function assertIsEmailAddress(){
  local _email="$1"
  if [[ "$_email" != *@* ]];
  then
    error "Error, $_email does not look like an email address"
    usage
    exit 1
  fi
  echo "$_email"
}

function writeEncrypted(){
  local _encrypted="$1"
  local _varname="$2"
  local _outputToFile="$3"
  if [[ "" == "$_outputToFile" ]]; then
    echo "$_encrypted"
    return 0;
  fi

  if [[ ! -f "$_outputToFile" ]]; then
    printf "
  ##########################################################################
  # Vault File Created with %s at %s
  ##########################################################################
  \n" "$(basename "$0")" "$(date)" >"$_outputToFile"
  fi
  ensureFileEndsInNewline "$_outputToFile"

  echo "$_encrypted" >> "$_outputToFile"
  echo "$_varname created and added to $_outputToFile"
}

# Append a trailing newline only if the file lacks one, so the next `>>` append starts on its
# own line rather than being glued onto the last one — which for a vault file would corrupt
# the preceding entry.
#
# Pure bash rather than the previous `sed -i -e '$a\'`: that spelling tripped SC1003, and this
# project bans in-place sed outright. Command substitution strips trailing newlines, so if the
# final byte IS a newline the capture is empty and nothing is appended; if it is any other
# character the capture is non-empty and one newline is added.
function ensureFileEndsInNewline(){
  local _filePath="$1"
  if [[ -s "$_filePath" ]] && [[ -n "$(tail -c 1 "$_filePath")" ]]; then
    printf '\n' >> "$_filePath"
  fi
}

function ansibleVersion(){
  (ansible --version | grep --color=never -Po '(?<=^ansible )([0-9.]+)' ) || (ansible --version | grep --color=never -Po '(?<=^ansible \[core )([0-9.]+)' )
}

function ansibleVersionAtLeast () {
    local atLeastVersion="$1"
    local extraErrorMessage="${2:-}"
    local ansibleVersion
    ansibleVersion="$(ansibleVersion)"
    if [[ "$atLeastVersion" == "$ansibleVersion" ]]
    then
        return 0
    fi
    # Convert version string to an array
    local IFS=.
    local atLeastVersionArray
    read -ra atLeastVersionArray <<< "$atLeastVersion"
    local ansibleVersionArray
    read -ra ansibleVersionArray <<< "$ansibleVersion"
    # fill empty fields in atLeastVersionArray with zeros
    local i
    for ((i=${#atLeastVersionArray[@]}; i<${#ansibleVersionArray[@]}; i++))
    do
        atLeastVersionArray[i]=0
    done
    for ((i=0; i<${#atLeastVersionArray[@]}; i++))
    do
        if [[ -z ${ansibleVersionArray[i]} ]]
        then
            # fill empty fields in ansibleVersionArray with zeros
            ansibleVersionArray[i]=0
        fi
        # the 10# forces bash to regard teh number as base-10 and not octal
        if ((10#${atLeastVersionArray[i]} > 10#${ansibleVersionArray[i]}))
        then
            error "Ansible version $ansibleVersion is lower than minimum version $atLeastVersion $extraErrorMessage"
            exitFromFunction
        fi
        if ((10#${atLeastVersionArray[i]} < 10#${ansibleVersionArray[i]}))
        then
            return 0
        fi
    done
    return 0
}


# Remove a vaulted variable and its whole `!vault |` ciphertext block from a vault file.
#
# A vaulted var is a YAML block scalar: the `varname:` line followed by indented
# continuation lines. Removing it means dropping the key line and every following line that
# is indented or blank, stopping at the next top-level key — which is what this does.
#
# Rewrites via a temp file and `mv` so the vault file is replaced ATOMICALLY. An in-place
# edit that is interrupted half-way through would leave a truncated vault file, i.e. destroy
# every other secret in it — a far worse outcome than the duplicate this exists to avoid.
function removeVaultedVarFromFile(){
  local _outputToFile="$1"
  local _varname="$2"
  local _tmp
  _tmp="$(mktemp "${_outputToFile}.XXXXXX")"
  awk -v var="$_varname" '
    BEGIN { skipping = 0 }
    # A new top-level key (non-indented, not a comment) always ends any skip.
    /^[^[:space:]#]/ {
      if (skipping && $0 !~ "^"var":") { skipping = 0 }
    }
    $0 ~ "^"var":" { skipping = 1; next }
    skipping {
      # Indented or blank lines belong to the block being removed.
      if ($0 ~ /^[[:space:]]/ || $0 ~ /^$/) { next }
      skipping = 0
    }
    { print }
  ' "$_outputToFile" > "$_tmp"
  chmod --reference="$_outputToFile" "$_tmp"
  mv -f "$_tmp" "$_outputToFile"
  echo "Removed existing '$_varname' block from $_outputToFile (replacing it)"
}

# validateOutputToFile <file> <varname> [allowReplace]
#
# By DEFAULT an existing varname is still a hard error — accidentally overwriting a live
# secret must stay difficult, and every existing caller keeps that behaviour unchanged.
# Passing allowReplace=1 is the opt-in that makes ROTATION possible: the old block is
# removed here so the caller's append writes the only definition of the key. Without this,
# rotating a vaulted credential required hand-editing the vault file, which is not something
# anyone should be asked to do by hand.
#
# The library's own CLAUDE.md listed "implement a way to update existing keys without
# recreating them" as a future improvement; this is that.
function validateOutputToFile(){
  local _outputToFile="$1"
  local _varname="$2"
  local _allowReplace="${3:-0}"
  local _outputToFileDirname
  if [[ "" != "$_outputToFile" ]]; then
    if [[ "$_outputToFile" != /* ]]; then
      echo "Error, outputToFile must be an absolute path, you have passed in: '$_outputToFile'. Try using \$(pwd)/path/to/file"
      exitFromFunction
    fi
    if [[ -f $_outputToFile ]]; then
      if [[ "" != "$(grep "^$_varname:" "$_outputToFile")" ]]; then
        if [[ "1" == "$_allowReplace" ]]; then
          removeVaultedVarFromFile "$_outputToFile" "$_varname"
        else
          echo " Error, $_varname already defined in file $_outputToFile"
          echo " (pass --replace to the calling script to rotate it in place)"
          exitFromFunction
        fi
      fi
    fi
    _outputToFileDirname="$(dirname "$_outputToFile")"
    echo "Ensuring $_outputToFileDirname directory exists"
    mkdir -p "$_outputToFileDirname" || echo "already exists"
  fi
}

function assertFilesExist(){
  for file in "$@";
  do
    if [[ "" == "$file" ]]; then
      echo "Empty file path"
      exitFromFunction
    fi
    if [[ ! -f $file ]]; then
      echo "No file found at $file"
      exitFromFunction
    fi
  done
}

function assertFilesDoNotExist(){
  for file in "$@";
  do
    if [[ "" == "$file" ]]; then
      echo "Empty file path"
      exitFromFunction
    fi
    if [[ -f $file ]]; then
      echo "Existing file found at $file"
      exitFromFunction
    fi
  done
}

function assertYqInstalled(){
    if ! command -v yq &>/dev/null; then
      echo '

      ERROR - this script requires yq v4+ to be installed

      Install with:

      sudo bash -c "wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"

      '
      exit 1
    fi

    # Check for yq v4+ (v3 uses "yq version", v4 uses "yq --version")
    local yqVersion
    yqVersion=$(yq --version 2>&1 | grep -oP 'v?\K[0-9]+' | head -1)
    if [[ "$yqVersion" -lt 4 ]]; then
      echo "
      ERROR - this script requires yq v4+, but you have v$yqVersion

      Upgrade with:

      sudo bash -c \"wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq\"

      "
      exit 1
    fi
}

function assertFileInEnv(){
  local filePath="$1"
  local env="$2"
  if [[ "$filePath" =~ environment/$env ]];
  then
    return
  fi
  echo "Filepath $filePath does not seem to be in environment/$env"
  exitFromFunction
}

function detectEnvironmentFromPath() {
  local filePath="$1"
  local inputEnv="$2"
  local detectedEnv=""
  
  # If no file path, just return the specified environment
  if [[ -z "$filePath" ]]; then
    echo "$inputEnv"
    return 0
  fi
  
  # Look for environment pattern in path and validate it exists
  if [[ "$filePath" == *"/environment/"* ]]; then
    # Extract potential environment from the path
    local pathEnv
    pathEnv=$(echo "$filePath" | grep -oP '(?<=/environment/)[^/]+')
    
    # Check if the found environment is in our valid environments list
    local validEnv=false
    for env in "${environmentArray[@]}"; do
      if [[ "$pathEnv" == "$env" ]]; then
        detectedEnv="$env"
        validEnv=true
        break
      fi
    done
    
    # If we found something in the path that looks like an environment but isn't valid
    if [[ "$validEnv" == "false" ]]; then
      error "Invalid environment '$pathEnv' detected in file path. Valid environments are: ${environmentArray[*]}"
      exitFromFunction
    fi
  fi
  
  # If no environment detected, return input environment
  if [[ -z "$detectedEnv" ]]; then
    echo "$inputEnv"
    return 0
  fi
  
  # If environment detected and no environment specified, use detected
  if [[ "$inputEnv" == "${defaultEnv:-}" ]]; then
    # Print message to stderr so it doesn't get captured as output
    echo "Detected environment '$detectedEnv' from file path. Using this environment instead of default." >&2
    echo "$detectedEnv"
    return 0
  fi
  
  # If environment detected and different from specified, error
  if [[ "$detectedEnv" != "$inputEnv" ]]; then
    error "Environment conflict: '$detectedEnv' detected in file path but '$inputEnv' specified as parameter."
    error "Either remove the environment parameter or ensure it matches the environment in the file path."
    exitFromFunction
  fi
  
  # Environment matches specified
  echo "$inputEnv"
  return 0
}