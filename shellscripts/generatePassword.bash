#!/usr/bin/env bash
set -euo pipefail
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
readonly noHeader="no header"
source ./_top.inc.bash

passwordLength=${1:-32}
password='='"$(openssl rand -base64 "$passwordLength")"

echo $password
