#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage(){
  echo "
USAGE:

This script bootstraps a complete mutual-TLS (mTLS) trust bundle for a service that
needs to present a SERVER certificate AND authenticate its clients with client
certificates signed by the same private CA. It is the server-side companion to
createVaultedSslClientCertificateAndAuth.bash (which only mints a CA + a client cert).

In ONE run it generates, from a single freshly-minted CA:
  - a self-signed CA           (ca.crt + ca.key)
  - a SERVER certificate       (server.crt + server.key)  extendedKeyUsage=serverAuth,
                                                           subjectAltName=DNS:<serverCn>
  - a CLIENT certificate       (client.crt + client.key)  extendedKeyUsage=clientAuth

All private keys are PASSWORDLESS PEM (unencrypted). This is REQUIRED: a TLS server
(nginx, docker registry:2, etc.) reads its server.key directly at startup and has no
mechanism to supply a key passphrase. If you need a password-protected CLIENT bundle
for interactive use, use createVaultedSslClientCertificateAndAuth.bash instead.

The four certificate/key values the SERVER needs are written to the Ansible vault
output file as encrypted strings, using the prefix you supply:

  <prefix>_ca_cert        <- ca.crt      (CA cert; server trusts clients signed by it)
  <prefix>_ca_key         <- ca.key      (CA private key; needed to issue more certs later)
  <prefix>_server_cert    <- server.crt  (the server certificate)
  <prefix>_server_key     <- server.key  (the server private key)

The CLIENT files (client.crt / client.key) are NOT vaulted — they are handed to a
consumer for distribution, and are left on disk in the working directory with the
ca.crt so you can immediately verify the chain end-to-end.

Usage: ./$(basename $0) [varname_prefix] [serverCn] [outputToFile] (optional: specifiedEnv - defaults to $defaultEnv) (optional: clientName) (optional: caSubject) (optional: certValidityDays) (optional: caValidityDays) (optional: extraSans)

Please note:
- The varname_prefix must start with 'vault_'
- serverCn is the server hostname; it becomes the server cert CN and its first SAN
- If outputToFile contains an environment path (e.g. environment/untrusted/...), that
  environment is used automatically and specifiedEnv can be omitted
- clientName defaults to 'client' (the client cert CN)
- caSubject defaults to '/C=GB/ST=England/O=LTS/OU=Infrastructure/CN=<serverCn> CA'
- certValidityDays defaults to 825 (server + client), caValidityDays to 3650
- extraSans is an optional comma-separated list of ADDITIONAL DNS SANs for the server cert

Examples:
# Container registry mTLS bundle in the untrusted vault (env auto-detected from the path):
./$(basename $0) vault_registry registry.priv.ballicom.com environment/untrusted/group_vars/all/vault_registry.yml

# Same, naming the client explicitly and adding a second SAN:
./$(basename $0) vault_registry registry.priv.ballicom.com environment/untrusted/group_vars/all/vault_registry.yml untrusted ci-runner '' 825 3650 registry.internal
    "
}

# Usage
if (( $# < 3 || $# > 9 ))
then
    usage
    exit 1
fi

# Set variables
readonly varname_prefix="$1"
readonly serverCn="$2"
outputToFile="$(getProjectFilePathCreateIfNotExists "${3:-}")"
readonly userSpecifiedEnv="${4:-$defaultEnv}"
readonly clientName="${5:-client}"
readonly caSubject="${6:-/C=GB/ST=England/O=LTS/OU=Infrastructure/CN=${serverCn} CA}"
readonly certValidityDays="${7:-825}"
readonly caValidityDays="${8:-3650}"
readonly extraSans="${9:-}"

# Set environment variable for _vault.inc.bash to use
readonly specifiedEnv="$userSpecifiedEnv"

# Source vault top
source ./_vault.inc.bash

# openssl is required in addition to ansible-vault (checked by _vault.inc.bash).
# command -v writes the resolved path to stdout only, so redirecting stdout is
# sufficient - this is a presence probe, not error suppression.
if ! command -v openssl >/dev/null; then
  error "openssl is not installed - it is required to generate the certificates"
  exit 1
fi

# The four vault variables this script produces. Keyed so that a prefix of
# 'vault_registry' yields exactly the names playbooks/imports/cnt/registry/play-registry.yml
# hard-requires (vault_registry_ca_cert / _ca_key / _server_cert / _server_key).
readonly varCaCert="${varname_prefix}_ca_cert"
readonly varCaKey="${varname_prefix}_ca_key"
readonly varServerCert="${varname_prefix}_server_cert"
readonly varServerKey="${varname_prefix}_server_key"

# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname_prefix"
if [[ -z "$serverCn" ]]; then
  error "serverCn (the server hostname / certificate CN) must not be empty"
  exit 1
fi
# Fail fast BEFORE generating anything if any target var is already present in the file.
validateOutputToFile "$outputToFile" "$varCaCert"
validateOutputToFile "$outputToFile" "$varCaKey"
validateOutputToFile "$outputToFile" "$varServerCert"
validateOutputToFile "$outputToFile" "$varServerKey"

# Build the server SAN line: always DNS:<serverCn>, plus any extra comma-separated DNS SANs.
sanLine="DNS:${serverCn}"
if [[ -n "$extraSans" ]]; then
  sanLine="${sanLine},DNS:${extraSans//,/,DNS:}"
fi
readonly sanLine

echo "Starting mutual-TLS bundle generation for server CN '$serverCn'"
workDir=/tmp/_mtls_keys
rm -rf "$workDir"
mkdir "$workDir"
cd "$workDir"

# File names
readonly fileCaKey="ca.key"
readonly fileCaCert="ca.crt"
readonly fileServerKey="server.key"
readonly fileServerCsr="server.csr"
readonly fileServerExt="server.ext"
readonly fileServerCert="server.crt"
readonly fileClientKey="client.key"
readonly fileClientCsr="client.csr"
readonly fileClientExt="client.ext"
readonly fileClientCert="client.crt"

echo "
#################################
Creating Certificate Authority
#################################
"
echo "Generating passwordless CA key at $workDir/$fileCaKey"
openssl genrsa -out "$fileCaKey" 4096
chmod 600 "$fileCaKey"

echo "Generating self-signed CA cert at $workDir/$fileCaCert (subject: $caSubject)"
openssl req -new -x509 \
  -key "$fileCaKey" \
  -out "$fileCaCert" \
  -days "$caValidityDays" \
  -sha256 \
  -subj "$caSubject"
chmod 644 "$fileCaCert"

echo "
#################################
Creating Server Certificate
#################################
"
echo "Generating passwordless server key at $workDir/$fileServerKey"
openssl genrsa -out "$fileServerKey" 4096
chmod 600 "$fileServerKey"

echo "Generating server CSR (CN=$serverCn)"
openssl req -new \
  -key "$fileServerKey" \
  -out "$fileServerCsr" \
  -subj "/C=GB/ST=England/O=LTS/OU=Infrastructure/CN=${serverCn}"

echo "Writing server extensions (serverAuth, SAN: $sanLine)"
cat > "$fileServerExt" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${sanLine}
EOF

echo "Signing server cert with the CA"
openssl x509 -req \
  -in "$fileServerCsr" \
  -CA "$fileCaCert" \
  -CAkey "$fileCaKey" \
  -CAcreateserial \
  -out "$fileServerCert" \
  -days "$certValidityDays" \
  -sha256 \
  -extfile "$fileServerExt"
chmod 644 "$fileServerCert"

echo "Verifying server cert against the CA"
openssl verify -CAfile "$fileCaCert" "$fileServerCert"

echo "
#################################
Creating Client Certificate
#################################
"
echo "Generating passwordless client key at $workDir/$fileClientKey"
openssl genrsa -out "$fileClientKey" 4096
chmod 600 "$fileClientKey"

echo "Generating client CSR (CN=$clientName)"
openssl req -new \
  -key "$fileClientKey" \
  -out "$fileClientCsr" \
  -subj "/C=GB/ST=England/O=LTS/OU=Developers/CN=${clientName}"

echo "Writing client extensions (clientAuth)"
cat > "$fileClientExt" <<'EOF'
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature
extendedKeyUsage=clientAuth
EOF

echo "Signing client cert with the CA"
openssl x509 -req \
  -in "$fileClientCsr" \
  -CA "$fileCaCert" \
  -CAkey "$fileCaKey" \
  -CAcreateserial \
  -out "$fileClientCert" \
  -days "$certValidityDays" \
  -sha256 \
  -extfile "$fileClientExt"
chmod 644 "$fileClientCert"

echo "Verifying client cert against the CA (sslclient purpose)"
openssl verify -purpose sslclient -CAfile "$fileCaCert" "$fileClientCert"

echo "
###################################################
Encrypting the four SERVER vault variables
###################################################
"
# Encrypt each file into an Ansible vaulted string and write it to the output file.
# The private keys never reach stdout in plaintext: openssl wrote them to files, and
# ansible-vault emits only ciphertext.
function vaultFileToVar(){
  local _sourceFile="$1"
  local _varname="$2"
  printf "\n# Encrypting %s as %s\n" "$_sourceFile" "$_varname"
  local _encrypted
  _encrypted="$(ansible-vault encrypt_string \
    --vault-id="$finalSpecifiedEnv@$vaultSecretsPath" \
    --stdin-name "$_varname" < "$workDir/$_sourceFile")"
  writeEncrypted "$_encrypted" "$_varname" "$outputToFile"
}

vaultFileToVar "$fileCaCert"     "$varCaCert"
vaultFileToVar "$fileCaKey"      "$varCaKey"
vaultFileToVar "$fileServerCert" "$varServerCert"
vaultFileToVar "$fileServerKey"  "$varServerKey"

echo "
###################################################
Done
###################################################

Vaulted the four SERVER variables into:
  ${outputToFile:-'(stdout - no output file supplied)'}

  $varCaCert
  $varCaKey
  $varServerCert
  $varServerKey

The CLIENT bundle for distribution (NOT vaulted) is in $workDir:
  $workDir/$fileClientCert
  $workDir/$fileClientKey
  $workDir/$fileCaCert   (the CA cert the client also needs)

To test the whole mTLS chain against a running server:
  curl --cacert $workDir/$fileCaCert \\
       --cert   $workDir/$fileClientCert \\
       --key    $workDir/$fileClientKey \\
       https://${serverCn}/

Issue more client certs later from the SAME CA by decrypting $varCaKey / $varCaCert
from the vault and re-running the client openssl steps against them.

The working directory $workDir still contains the CA and server PRIVATE KEYS in
plaintext. Delete it once you have distributed the client bundle:
  rm -rf $workDir
"
