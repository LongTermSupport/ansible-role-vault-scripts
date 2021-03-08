#!/usr/bin/env bash
readonly scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$scriptDir" || exit 1
# Set up bash
readonly noHeader="no header"
source ./_top.inc.bash

readonly passwordLength=${1:-32}
readonly password='=+'"$(openssl rand -base64 "$passwordLength")"

echo $password
