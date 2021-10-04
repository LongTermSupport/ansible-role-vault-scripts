#!/usr/bin/env bash
readonly scriptDir="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd -P)"
cd "$scriptDir"
# Set up bash
source ./_top.inc.bash

function usage(){
  echo "

USAGE:

This script will generate a random password and then use this to create a certificate authority (CA) which is then
used to create a client certificate which can be used with nginx etc for client SSL based authentication

This script does not currently support creating more than one client SSL certificate, though it would not be a
difficult thing to add in

Usage ./$(basename $0) [varname_prefix] [subj] (optional: outputToFile) (optional: specifiedEnv - defaults to
$defaultEnv) (optional: keepKeys) (optional: clientSub)

Please note, the varname_prefix must start with 'vault_'

e.g

./$(basename $0) vault_client_foo '/C=GB/ST=England/L=Shipley/O=Foo Ltd/CN=Foo Ltd/emailAddress=info@ltscommerce.dev'

To generate the following:

client_foo_ca.pass.key
client_foo_ca.pem

    "
}

# Usage
if (( $# < 2 ))
then
    usage
    exit 1
fi

# Set variables
readonly varname_prefix="$1"
readonly subj="$2"
readonly outputToFile="$(getProjectFilePathCreateIfNotExists "${3:-}")"
readonly specifiedEnv="${4:-$defaultEnv}"
readonly clientSubj="${5:-"${subj/CN=/CN=Client }"}"

# Source vault top
source ./_vault.inc.bash


# Assertions
assertValidEnv "$specifiedEnv"
assertPrefixedWithVault "$varname_prefix"
validateOutputToFile "$outputToFile" "$varname_prefix"
if [[ "$subj" == "$clientSubj" ]]; then
  error "The subj and clientSubj strings must not be identical, the CN (common name) must be different"
  exit 1
fi

echo "Starting process to generate keys"
workDir=/tmp/_keys
rm -rf $workDir
mkdir $workDir
# clean up temp files on exit
trap "rm -rf $workDir" EXIT


cd $workDir



echo "
#################################
Creating Certificate Authority
#################################
"
#files
readonly fileCaPassfile="ca_pass.txt"
readonly fileCaKey="ca.key"
readonly fileCaCert="ca.crt"
readonly fileSSLConfig="ssl_config.conf"

echo "Creating Config File as $workDir/$fileSSLConfig"
cat <<'EOF' > "$fileSSLConfig"
#
# OpenSSL example configuration file.
# This is mostly being used for generation of certificate requests.
#
# You might want to copy this into /etc/ssl/ or define OPENSSL_CONF
#

# This definition stops the following lines choking if HOME isn't
# defined.
HOME                    = .
RANDFILE                = $ENV::HOME/.rnd

# Extra OBJECT IDENTIFIER info:
#oid_file               = $ENV::HOME/.oid
oid_section             = new_oids

# To use this configuration file with the "-extfile" option of the
# "openssl x509" utility, name here the section containing the
# X.509v3 extensions to use:
# extensions            =
# (Alternatively, use a configuration file that has only
# X.509v3 extensions in its main [= default] section.)

[ new_oids ]

# We can add new OIDs in here for use by 'ca', 'req' and 'ts'.
# Add a simple OID like this:
# testoid1=1.2.3.4
# Or use config file substitution like this:
# testoid2=${testoid1}.5.6

# Policies used by the TSA examples.
tsa_policy1 = 1.2.3.4.1
tsa_policy2 = 1.2.3.4.5.6
tsa_policy3 = 1.2.3.4.5.7

####################################################################
[ ca ]
default_ca      =  CA_default                           # The default ca section

####################################################################
[ CA_default ]

dir             = .                                     # Where everything is kept
certs           = $dir                          # Where the issued certs are kept
crldir          = $dir                              # Where the issued crl are kept
database        = $dir                       # database index file.
unique_subject  = yes                                   # Set to 'no' to allow creation of
                                                        # several ctificates with same subject.
new_certs_dir   = $certs                                # default place for new certs.

certificate     = $certs/rootcrt.pem                    # The CA certificate
serial          = $dir/serial.txt                       # The current serial number
crlnumber       = $dir/crlnumber                        # the current crl number
                                                        # must be commented out to leave a V1 CRL
crl             = $crldir/crl.pem                       # The current CRL
private_key     = $dir/private/rootprivkey.pem          # The private key
RANDFILE        = $dir/private/.rand                    # private random number file

#x509_extensions        = usr_cert                              # The extentions to add to the cert

# Comment out the following two lines for the "traditional"
# (and highly broken) format.
name_opt        = ca_default                            # Subject Name options
cert_opt        = ca_default                            # Certificate field options

# Extension copying option: use with caution.
copy_extensions = copy

# Extensions to add to a CRL. Note: Netscape communicator chokes on V2 CRLs
# so this is commented out by default to leave a V1 CRL.
# crlnumber must also be commented out to leave a V1 CRL.

# crl_extensions        = crl_ext

default_days    = 365           # how long to certify for
default_crl_days= 30                    # how long before next CRL
default_md      = default               # use public key default MD
preserve        = no                    # keep passed DN ordering

# A few difference way of specifying how similar the request should look
# For type CA, the listed attributes must be the same, and the optional
# and supplied fields are just that :-)
policy          = policy_match

# For the CA policy
[ policy_match ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

# For the 'anything' policy
# At this point in time, you must list all acceptable 'object'
# types.
[ policy_anything ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

####################################################################
[ req ]
default_bits            = 4096
default_keyfile         = priv.key.pem
distinguished_name      = req_distinguished_name
attributes              = req_attributes
x509_extensions         = v3_ca
req_extensions          = v3_req


# req_extensions = v3_req # The extensions to add to a certificate request

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
countryName_default             =
countryName_min                 = 2
countryName_max                 = 2

stateOrProvinceName             = State or Province Name (full name)
stateOrProvinceName_default     =
localityName                    = Locality Name (eg, city)
localityName_default            =

0.organizationName              = Organization Name (eg, company)
0.organizationName_default      =

# SET-ex3                       = SET extension number 3

[ req_attributes ]
#challengePassword              = A challenge password
#challengePassword_min          = 4
#challengePassword_max          = 20
#unstructuredName               = An optional company name

[ usr_cert ]

# These extensions are added when 'ca' signs a request.

# This goes against PKIX guidelines but some CAs do it and some software
# requires this to avoid interpreting an end user certificate as a CA.

basicConstraints=CA:FALSE

# PKIX recommendations harmless if included in all certificates.
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer

[ v3_req ]

# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment

[ v3_ca ]
# Extensions for a typical CA
# PKIX recommendation.
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer:always
basicConstraints = CA:true
EOF

echo "Generating a random CA key pass and saving it to $workDir/$fileCaPassfile"
"$scriptDir"/generatePassword.bash > "$fileCaPassfile"

echo "Saving CA Key to $workDir/$fileCaKey"
openssl genrsa \
    -aes256 \
    -passout file:"$fileCaPassfile" \
    -out "$fileCaKey" 4096

echo "Saving CA Cert to $workDir/$fileCaCert"
openssl req \
    -config "$fileSSLConfig" \
    -key "$fileCaKey" \
    -new \
    -x509 \
    -days 7300 \
    -sha256 \
    -extensions v3_ca \
    -out "$fileCaCert" \
    -subj  "$subj" \
    -passin file:"$fileCaPassfile"

echo "Running openssl x509"
openssl x509 \
    -noout \
    -text \
    -in "$fileCaCert"  \
    -passin file:"$fileCaPassfile"

echo "
#################################
Creating Client Certificates
#################################
"
#files
readonly fileClientPass="client_pass.txt"
readonly fileClientKey="client.key"
readonly fileClientCsr="client.csr"
readonly fileClientCert="client.crt"
readonly fileClientP12="client.p12"
readonly fileClientP12Base64="client.p12.b64"


echo "Generating a random client key pass and saving it to $workDir/$fileClientPass"
"$scriptDir"/generatePassword.bash > "$fileClientPass"

echo "Creating client key at $workDir/$fileClientKey"
openssl genrsa \
    -des3 \
    -passout file:"$fileClientPass" \
    -out "$fileClientKey" 1024

echo "Creating client CSR at $workDir/$fileClientCsr"
openssl req \
    -new \
    -passin file:"$fileClientPass" \
    -key "$fileClientKey" \
    -out "$fileClientCsr" \
    -subj "$clientSubj"

echo "Creating certificate at $workDir/$fileClientCert"

openssl x509 \
    -req \
    -days 1095 \
    -passin file:"$fileCaPassfile" \
    -in "$fileClientCsr" \
    -CA "$fileCaCert" \
    -CAkey "$fileCaKey" \
    -set_serial 01 \
    -out "$fileClientCert"

echo "Verifying Client Cert"
openssl verify -purpose sslclient -CAfile $fileCaCert $fileClientCert
echo "done"

rm "$fileClientCsr"

echo "
#################################
Creating Ansible Vaulted Strings
#################################
"
for f in $workDir/*; do
  fileName="$(basename $f)"
  case "$fileName" in
    "$fileSSLConfig")
      continue
    ;;
  esac
  varname="${varname_prefix}__${fileName//\./_}"
  printf "\n\n# Encrypting %s as %s\n" "$fileName" "$varname"
  encrypted="$(cat "$f" | ansible-vault encrypt_string \
    --vault-id="$specifiedEnv@$vaultSecretsPath" \
    --stdin-name "$varname")"

  writeEncrypted "$encrypted" "$varname" "$outputToFile"

done
rm -rf $workDir

echo "

To use this:


Configure Nginx:

    ssl_client_certificate /path/to/ca.cert;
    ssl_verify_client on;

Use CURL (for example) to access:

  curl --cert client.crt --key client.key --cacert ca.cert https://protected.domain.com


To get the contents of the files you can use the dumpGroupSecrets.bash script, eg

bash ./shellscripts/vault/dumpGroupSecrets.bash prod vault_client_foo__client_pass_txt 2>/dev/null

Or of course you can (should) use Ansible to create files etc as required in your various environments

"
