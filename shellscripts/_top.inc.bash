# Check if scriptDir has been defined
if [[ -z "$scriptDir" ]]; then
  echo '
scriptDir has not been defined, this should be set using something like:

  readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"

Exiting
  '
  exit 1
fi

# assumes scriptDir is shellscripts/vault
readonly projectDir="$(dirname "$( dirname "$scriptDir")")"

if [[ ! -f $projectDir/ansible.cfg ]]; then
  echo "

  Failed to find project root directory, or the project does not contain ansible.cfg file

  "
  exit 1
fi

# Make BASH fail more safely
set -Ee
set -u
set -o pipefail

# Better handling of white space
standardIFS="$IFS"
IFS=$'\n\t'

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
# Error Handling Ends



echo "
===========================================
$(hostname 2 &>/dev/null || echo 'no hostname set') $0 $@
===========================================
"
