# Check if scriptDir has been defined
if [[ -z "$scriptDir" ]]; then
  echo '
scriptDir has not been defined, this should be set using something like:

  readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"

Exiting
  '
  exit 1
fi


#####################################
## Make BASH fail more safely
#  Exit  immediately  if a pipeline (which may consist of a single simple command), a list, or a compound command
#  (see SHELL GRAMMAR above), exits with a non-zero status.  The shell does not exit if the command  that
#  fails  is part of the command list immediately following a while or until keyword, part of the test following
#  the if or elif reserved words, part of any command executed in a && or || list except the command  following
#    the  final  &&  or  ||, any command in a pipeline but the last, or if the command's return value is
#  being inverted with !.  If a compound command other than a subshell returns a  non-zero  status  because  a
#  command  failed  while  -e  was being ignored, the shell does not exit.  A trap on ERR, if set, is executed
#  before the shell exits.  This option applies to the shell environment and each subshell  environment  separately
#  (see COMMAND EXECUTION ENVIRONMENT above), and may cause subshells to exit before executing all the commands
#  in the subshell.
#
#  If a compound command or shell function executes in a context where -e is being ignored, none of  the  commands
#    executed within the compound command or function body will be affected by the -e setting, even if -e
#  is set and a command returns a failure status.  If a compound command or shell function sets -e while  executing
#  in  a context where -e is ignored, that setting will not have any effect until the compound command or the command
#  containing the function call completes.
set -o errexit

# If  set, command substitution inherits the value of the errexit option, instead of unsetting it in the sub‐
# shell environment.  This option is enabled when posix mode is enabled.
shopt -s inherit_errexit

# Treat  unset  variables  and parameters other than the special parameters "@" and "*" as an error when per‐
# forming parameter expansion.  If expansion is attempted on an unset variable or parameter, the shell prints
# an error message, and, if not interactive, exits with a non-zero status.
set -u

# If set, any trap on ERR is inherited by shell functions, command substitutions, and commands executed in  a
# subshell environment.  The ERR trap is normally not inherited in such cases.
set -E

# If set, the return value of a pipeline is the value of the last (rightmost) command to exit with  a
# non-zero  status,  or  zero if all commands in the pipeline exit successfully.  This option is disabled by default.
set -o pipefail

# Better handling of white space
standardIFS="$IFS"
IFS=$'\n\t'

######################################
# Error Handling
backTraceExit() {
  local err=$?
  set +o xtrace
  local code="${1:-1}"
  printf "\n\nError in ${BASH_SOURCE[1]}:${BASH_LINENO[0]}. '${BASH_COMMAND}'\n\n exited with status: \n\n$err\n\n"
  # Print out the stack trace described by $function_stack
  if [ ${#FUNCNAME[@]} -gt 2 ]; then
    echo "Call tree:"
    for ((i = 1; i < ${#FUNCNAME[@]} - 1; i++)); do
      echo " $i: ${BASH_SOURCE[$i + 1]}:${BASH_LINENO[$i]} ${FUNCNAME[$i]}(...)"
    done
  fi
  echo "Exiting with status ${code}"
  exit "${code}"
}
trap 'backTraceExit' ERR
set -o errtrace

# Functions Abort Script
trap "exit 1" TERM
export TOP_PID=$$
function exitFromFunction(){
  kill -s TERM $TOP_PID
}

# Error Handling Ends

######################################
## FUNCTIONS that are used in setting readonly vars before we include the vault stuff

# for abs paths just use them, otherwise check for path to file in project root
function getFilePath(){
  local _filePath="$1"
  if [[ -f "$_filePath" ]]; then
    realpath "$_filePath"
    return 0
  fi
  if [[ -f "$projectDir/$_filePath" ]]; then
    realpath "$projectDir/$_filePath"
    return 0
  fi
  error "Failed finding file path for $_filePath"
  exitFromFunction
}

function getFilePathOrEmptyString(){
  local _filePath="$1"
  if [[ "" == "$_filePath" ]]; then
    echo ""
    return 0
  fi
  getFilePath "$_filePath"
}

function getProjectFilePathCreateIfNotExists(){
  local _filePath="$1"
  if [[ "" == "$_filePath" ]]; then
    echo ""
    return 0
  fi
  if [[ "$_filePath" != "$projectDir"* ]]; then
    _filePath="$projectDir/$_filePath"
  fi
  if [[ -f "$_filePath" ]]; then
    realpath "$_filePath"
    return 0
  fi
  mkdir -p "$(dirname "$_filePath")"
  touch "$_filePath"
  realpath "$_filePath"
}


# Write a formatted error message to stderr
function error() {
  printf "\n\n########################\n### ERROR: %s\n########################\n\n" "$*" >&2;
}

function findAnsibleCfgDir(){
  local cwd ansibleCfgPath
  cwd="$(pwd)"
  ansibleCfgPath="$cwd/ansible.cfg"
  while [[ "$cwd" != "/" && ! -f "$ansibleCfgPath" ]]; do
    cwd="$(dirname "$cwd")"
    ansibleCfgPath="$cwd/ansible.cfg"
  done
  if [[ -f "$ansibleCfgPath" ]]; then
    echo "$cwd"
    return 0
  fi
  error "Failed finding ansibleCfgPath" >&2
  return 0
}

if [[ '' == "${noHeader:=''}" ]]; then
  ######################################
  ## Some useful info to output
  echo "
===========================================
$(hostname &>/dev/null || echo 'no hostname set') $0 $@
===========================================
"
fi

# assumes scriptDir is shellscripts/vault
#readonly projectDir="$(dirname "$( dirname "$scriptDir")")"
readonly projectDir="$(findAnsibleCfgDir)"

if [[ ! -f $projectDir/ansible.cfg ]]; then
  echo "

  Failed to find project root directory, or the project does not contain ansible.cfg file

  "
  exit 1
fi