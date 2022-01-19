

function assertValidEnv(){
  local _env="$1"
  if [[ "${environmentArray[*]}" == *${_env}* ]]; then
    return 0
  fi
  error "Error, specified env $_env is not found in ${environmentArray[*]}"
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
  \n" "$(basename $0)" "$(date)" >"$_outputToFile"
  fi
  ensureFileEndsInNewline "$_outputToFile"
  echo "$_encrypted" >> "$_outputToFile"
  echo "$_varname created and added to $_outputToFile"
}

# @see https://unix.stackexchange.com/a/31955
function ensureFileEndsInNewline(){
  local _filePath="$1"
  sed -i -e '$a\' "$_filePath"
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


function validateOutputToFile(){
  local _outputToFile="$1"
  local _varname="$2"
  local _outputToFileDirname
  if [[ "" != "$_outputToFile" ]]; then
    if [[ "$_outputToFile" != /* ]]; then
      echo "Error, outputToFile must be an absolute path, you have passed in: '$_outputToFile'. Try using "'$(pwd)/path/to/file'
      exitFromFunction
    fi
    if [[ -f $_outputToFile ]]; then
      if [[ "" != "$(grep "^$_varname:" $_outputToFile)" ]]; then
        echo " Error, $_varname already defined in file $_outputToFile"
        exitFromFunction
      fi
    fi
    _outputToFileDirname="$(dirname $_outputToFile)"
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
    if [[ ! -f /usr/bin/yq ]]; then
      echo '

      ERROR - this script requires yq to be installed

      You might want to install with a command like:

      sudo bash -c "wget https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"

      '
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