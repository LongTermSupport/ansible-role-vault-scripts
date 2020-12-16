function error() {
  printf "\n########################\n### ERROR: %s\n########################" "$*" >&2;
}

function assertValidEnv(){
  local _env="$1"
  if [[ "${environmentArray[*]}" == *${_env}* ]]; then
    return 0
  fi
  error "Error, specified env $_env is not found in ${environmentArray[*]}"
  return 1
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
  \n" "$(basename $0)" "$(date)" >"$_outputToFile"
  fi

  echo "$_encrypted" >> "$_outputToFile"
  echo "$_varname created and added to $_outputToFile"
}

function ansibleVersion(){
  ansible --version | grep --color=never -Po '(?<=^ansible )([0-9.]+)'
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
            return 1
        fi
        if ((10#${atLeastVersionArray[i]} < 10#${ansibleVersionArray[i]}))
        then
            return 0
        fi
    done
    return 0
}


function validateOutputToFile(){
  local _outputToFile="$1"
  local _varname="$2"
  local _outputToFileDirname
  if [[ "" != "$_outputToFile" ]]; then
  if [[ "$_outputToFile" != /* ]]; then
    echo "Error, outputToFile must be an absolute path, you have passed in: '$_outputToFile'. Try using "'$(pwd)/path/to/file'
    exit 1
  fi
  if [[ -f $_outputToFile ]]; then
    if [[ "" != "$(grep $_varname $_outputToFile)" ]]; then
      echo " Error, $_varname already defined in file $_outputToFile"
      exit 1
    fi
  fi
  _outputToFileDirname="$(dirname $_outputToFile)"
  echo "Ensuring $_outputToFileDirname directory exists"
  mkdir -p "$_outputToFileDirname" || echo "already exists"
fi
}