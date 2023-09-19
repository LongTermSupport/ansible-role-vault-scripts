#!/bin/bash
# Check if scriptDir has been defined
if [[ -z "$scriptDir" ]]; then
  echo '
scriptDir has not been defined, this should be set using something like:

  readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"

Exiting
  '
  exit 1
fi

source $scriptDir/_top.inc.bash

allEnvPaths="$(find $projectDir -maxdepth 2 -wholename '*/environment/*' -type d)"
allEnvNames="$(echo "$allEnvPaths" | sed 's/.*\/\(.*\)/\1/')"
placeholderEnvName='_env_'

function assertContainsPlaceholder(){
  local _toCheck="$1"
  if [[ "$_toCheck" != *"$placeholderEnvName"* ]]; then
    echo "ERROR: Failed finding placeholderEnvName $placeholderEnvName in $_toCheck"
    echo "you must use $placeholderEnvName for the environment name when running this script"
    return 1
  fi
}