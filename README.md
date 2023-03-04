# Vault Scripts

This role is primarly a container for some utility shell scripts to assist with working Ansible vault, specifically
using encrypt-string

These have been packaged as a role to assist with integrating these with your ansible projects

To install this into your project, first you need to add the following to your `requirements.yml` file:

```yaml
# Vault Script
- src: https://github.com/LongTermSupport/ansible-role-vault-scripts
  scm: git
  name: lts.vault-scripts
  version: master
```

Then to install your roles, the following command is suggested:

```bash
ansible-galaxy install \
        --force \
        --keep-scm-meta \
        --role-file={{ requirements_path }} \
        --roles-path={{ roles_path }}
```

You should set up a symlink from your project shellscripts folder to the shellscripts in the role:

```bash
cd {{ project_root }}
mkdir shellscripts
cd shellscripts
ln -s ../{{ roles_path }}/lts.vault-scripts/shellscripts/ vault
```

## Prerequisites

You must have the following set up for these to work:

* scripts installed to `shellscripts/vault` or otherwise a subdirectory 2 deep from your project root
* `ansible.cfg` file in the root of your project
* `environment/dev` folder containing your default dev environment (or whichever env name you choose to use)
* You have the line `*.secret` in your project `.gitignore` file
* You need to have `yq` installed
    * You can install this with something like:

```
sudo bash -c "wget https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq"  
```

## Limitations

* vaulted variables must be prefixed with `vault_`
* vaulted variables must be top level variables, not part of any nested structure.

It is suggested that whilst these are limitations, it is not necessarily a bad style to have to conform to. If you need
to encrypt things in a nested structure, you will need to define them as a top level vaulted variable and then use that
vaulted variable in your nested structure.

## Instructions for Scripts

For each script, execute without arguments to get usage instructions

### Default and Specified Environment

For all actions, an environment name is required. This will default to `dev`.

You can override this on a per script call basis by passing the env name for the `specifiedEnv` parameter, for example:

```bash
bash shellscripts/vault/generateVaultSecret.bash prod
```

Alternatively, you can `export vaultScriptsDefaultEnv='prod'` to define a default environment for your current session,
for example

```bash
export vaultScriptsDefaultEnv=prod

bash shellscripts/vault/generateVaultSecret.bash

bash shellscripts/vault/createVaultedPassword.bash vault_pass_user_foo ./environment/$vaultScriptsDefaultEnv/group_vars/all/vault_user_passwords.yml

bash shellscripts/vault/createVaultedSshKeyPair.bash vault_default ops@domain.com ./environment/$vaultScriptsDefaultEnv/group_vars/all/vault_ssh_keys.yml
```

### Generate Vault Secret

This script will generate a secret file for you with a good long chunk of random text

```bash
bash shellscripts/vault/generateVaultSecret.bash
```

eg `vault-pass-dev.secret`

```
85E88clxKzfNtC/Hdh4vKD5GMdY0vbbBPq/9zQJvWD2XSg/g+sv+wSlFXbgPGG2B502/MXV0DvUI1kbcKw+w2IX2knIeZdhw7LSRT8yXBuQQxCkbrfsZaxH/avljFMgdds/bmL/aFedkFMhngLn0xXGlcGgxukr7jv5uBZx/B4kMK92kO9xpOBuRa/I8cs5bY777ZWuS009ZN4WJVXByDe49lLj29FmtXy64A+XsaOzvrM9YM7K5kURfDF0woQV1zjR
+lMRf/FLKBRdCJ1L1YhKKlBUMPK9kpNPbj1mq5eZ33nqKGEywNaBwJO8T/Jhe/4BPJIa2kyDZFU0kzWKWv+90FfDxUchpeOghzXdWjPJBGXGvyS6Pe/c8t+RTTduMge/rBO7ANziPXSQOT3271KnF7sgaHzWjU9t3/GXRx+bJ/s3/Tgjz9suLtuKJwI/gaPAWx2DABa6/ggXI8F+qdQomdFQ6hyJWPVYpLdcedm6/SMC80Io9He+94VD02Whl74bqS0/+JF/k5zVUyunGcbR2jRmYpixTwnuve5RPDZ6WgoSwbEblXtqpm34U2C35IEz71gOImPax5qrNylnv8iY7GxIu1ryO1x0JZ
yO5oVDAsRwF/aISUeqj5h2wg/L2829MnRONmQ7NIz5adYsabsb8hAON9nzhHdgQ6CbnKtgpe5OwzqmwPb4E1zgNpoXd1vZfzd+EfP1YvBK/uQjuIE6p5jYX/gIzYn+4dfrUVtjX1pHs7XSGKGEnZ6L32+APZwMmTpA2T6GoqLi+9RYmsAQtygSHGuyuCeYDz5Dg2wbygWLhItZSW6gt7zSc6+MYL6m4rHcUXJxMAv5sI3MmTUQZEfjBxRr3BYjSaygCn6LaI4M5aMdQ/ikyleh/5Ts/TvFatsc5LAxVwRLpaSfs8kKYfqeRUBhx8ImM6pOrZOvOPzpyKDehl7hzdMPTxAqbgEsm5B+xs8+UTL7Ztcmtqc6iGGU+4yuDNzR/tjadyZQiP+mOg5RZV
uva18Gg9VRrd9vDSugsm2389lhWx5Dwx5y1W8yKKBDAASYKeCgDrxtqYonW0grz0LrnBOrU1zXKHtdEhsMbzpXDU3nKHF2PDIHxupVXtzXrVPecOsJ2UrrBhLu29H4r68yq5k
```

You can pass a second `update` argument if you want to overwrite an existing file, but of course be careful with that

You should ensure your secret files are NOT tracked by git and are never committed. Instead you MUST make sure you note
down the secret file contents wherever you manage secrets, eg a password manager or other secure secrets storage system

(Note - Ansible 2.10 allows storing multiple keys in a single file prefixed with the key ID, however for the sake of
backwards compat, we use a separate file for each key. You could choose to consolidate these into a single file if you
are using 2.10 or greater)

### Create Vaulted Password

This script will generate as password string and then encrypt it for you, generating yaml that assigns the encrrypt
password to the specified variable

For example, in the `dev` environment, generate a password and vault it, then write it to the
file `./environment/dev/vault_user_passwords.yml` assigned to the variable `vault_pass_user_foo`

```bash

bash shellscripts/vault/createVaultedPassword.bash vault_pass_user_foo ./environment/dev/group_vars/all/vault_user_passwords.yml

```

As above, but instead of writing to file, just write to stdout so that you can copy paste it manually where ever you
want

```bash

bash shellscripts/vault/createVaultedPassword.bash vault_pass_user_foo

```

#### Generating a lot of passwords

If you want to generate a bunch of passwords, you might want to do something like this:

```bash
while read -r item; do 
  printf "\n- $item"; 
  bash shellscripts/vault/createVaultedPassword.bash $item ./environment/staging/group_vars/all/vault_wordpress.yml staging; 
done <<< "vault_wordpress_auth_key
vault_wordpress_secure_auth_key
vault_wordpress_logged_in_key
vault_wordpress_nonce_key
vault_wordpress_auth_salt
vault_wordpress_secure_auth_salt
vault_wordpress_logged_in_salt
vault_wordpress_nonce_salt"
```


### Create Vaulted String - eg Encrypt Specific Password or Other Secret

If you need to encrypt a password that is predefined or has specific requirements not met by the auto generated password
created with createVaultedPassword.bash then you can use this script

For example, if we need a shorter password than the standard one:

```bash
bash shellscripts/vault/createVaultedString.bash vault_pass_user_foo "$(bash shellscripts/vault/generatePassword.bash 20)"
```

### Create Vaulted SSH Key Pair

This script will generate password protected private and public keys, encrypt them as strings and then assign the
passphrase and the public/private key to variables that are prefixed with teh prefix you specify. Finally this can
optionally be written directly to the file you specify as normal

For example

```bash

# echo to stdout
bash shellscripts/vault/createVaultedSshKeyPair.bash vault_default ops@domain.com

# write directly to file
bash shellscripts/vault/createVaultedSshKeyPair.bash vault_default ops@domain.com ./environment/dev/group_vars/all/vault_ssh_keys.yml

```

Will generate the following variables (truncated for readability):

```yaml

vault_default_id_passphrase: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  37383634643132346565376332663265363435316431323236626561626263373965366230313035 (...)
vault_default_id: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  63373964336530653133336565306533626165646338633061636363666132363731656632636435 (...)
vault_default_id_pub: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  37666166393434346539356139393432636134633239643531623761396333323761313435663136 (...)


```

### Create Vaulted SSH Deploy Key Pair

This script will generate private and public keys with no passsword protection, encrypt them as strings and then assign
the public/private key to variables that are prefixed with teh prefix you specify.

**_Please do not use this for anything other than read only deploy keys_**

Finally this can optionally be written directly to the file you specify as normal

For example

```bash

# echo to stdout
bash shellscripts/vault/createVaultedSshDeployKeyPair.bash vault_github_deploy ops@domain.com

# write directly to file
bash shellscripts/vault/createVaultedSshKeyPair.bash vault_github_deploy ops@domain.com ./environment/dev/group_vars/all/vault_ssh_keys.yml

```

Will generate the following variables (truncated for readability):

```yaml

vault_github_deploy_id: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  63373964336530653133336565306533626165646338633061636363666132363731656632636435 (...)
vault_github_deploy_id_pub: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  37666166393434346539356139393432636134633239643531623761396333323761313435663136 (...)


```

### Create Vaulted SSL Client Certificate and Authority

If you want to secure an HTTP endpoint using client SSL certificates then this is a nice solution. This will create a
certificate authority and generate the client certificate that you can install or use with any client that needs to
access the HTTP endpoint.

Client certificates are a nice alternative to basic auth. It is not brute forceable at all, you must have the correct
client certificate installed to be able to access an endpoint secured with client SSL.

Usage:

```bash

bash shellscripts/vault/createVaultedSslClientCertificateAndAuth.bash \
  [varname_prefix] \
  [subj] \
  (optional: outputToFile) \
  (optional: specifiedEnv - defaults to $defaultEnv) \
  (optional: keepKeys) (optional: clientSub)

# For example:
bash shellscripts/vault/createVaultedSslClientCertificateAndAuth.bash \
  vault_client_foo \
  '/C=GB/ST=England/L=Shipley/O=Foo Ltd/CN=Foo Ltd/emailAddress=info@foo.dev' \
   ./environment/prod/group_vars/all/vault_client_certs_foo.yml \
   prod

```

To use this:


Configure Nginx:

    ssl_client_certificate /path/to/ca.cert;
    ssl_verify_client on;

Use CURL (for example) to access:

    curl --cert client.crt --key client.key --cacert ca.cert https://protected.domain.com


To get the contents of the files you can use the dumpGroupSecrets.bash script, eg

    bash ./shellscripts/vault/dumpGroupSecrets.bash prod vault_client_foo__client_pass_txt 2>/dev/null

Or of course you can (should) use Ansible to create files etc as required in your various environments

### Copy File Between Environments, Rekeying the Encrypted Variables

There are some (few) scnearios where you need to have the exact same values shared between dev and prod environments.
Gnerally you would want all passwords etc to be totally unique between environments however there could be a situation
where there is a value that must be the same between environments. For that situation, we have this script

Usage:

```bash

[currentEnv] [newEnv] [vaultFilePaths ...]

# For example
bash -x shellscripts/vault/copyVaultFileToEnvironment.bash \
  prod \
  dev \
  ./environment/prod/group_vars/all/vault_client_certs_foo.yml \
  ./environment/prod/group_vars/all/vault_client_certs_bar.yml 

```

In the above example, two client certificate secrets are copied from prod to dev. You can then delete the variables you
do not need in dev, but can keep the ones you do need - for example the client certificates that might be required to
authenticate against some prod resource.

### Dump Secrets in Files

This script will take a file glob of files that you want to pull vaulted variables out of. It will then use `yq` to
parse out all the variables, find the vaulted ones, decrypt them and then dump all the output

This can be convenient if you just want to look at a single file

It is the only solution for dumping host_var level secrets, or secrets in vars files or any other arbitrary file that
may have secrets in.

You are encouraged to store the majority of your secrets with the `group_vars` folder for your environment and can use
the `dumpGroupSecrets.bash` script to dump these in bulk, or pull out a single variable, though you can use this script
for group vars as well if you prefer

Usage:

```bash
# Dump all host_vars files
bash shellscripts/vault/dumpSecretsInFiles.bash dev environment/dev/host_vars/*.yml

# Dump all group_vars files
bash shellscripts/vault/dumpSecretsInFiles.bash dev environment/dev/group_vars/all/*.yml
```

### Dump Group Var Secrets

Once you have some secrets stored in an environment folder, you will probably want a way to easily view them

**_Note: this will only give you secrets in your group_vars - it will not include host_vars level secrets**
If you want to view host secrets, use the `dumpSecretsinFiles.bash` script which can decrypt any file

For this, you can use this script

For example, to view all group_vars secrets in the dev environment

```bash
bash shellscripts/vault/dumpGroupSecrets.bash
```

Or you can dump a single secret:

```bash
bash shellscripts/vault/dumpGroupSecrets.bash vault_root_pass
```

Example output:

```
bash shellscripts/vault/dumpSecrets.bash dev

===========================================
 shellscripts/vault/dumpGroupSecrets.bash dev
===========================================


PLAY [Ansible Ad-Hoc] ***************************************************************************************************************

TASK [vault-scripts : Parse Vault Variables] ****************************************************************************************
changed: [localhost -> localhost]

TASK [vault-scripts : Debug vaultvars] **********************************************************************************************
ok: [localhost] => 
  vaultvars:
    changed: true
    cmd: |-
      grep -rhPo '^[^:]+(?=: )' /opt/Projects/ansible-scratch/environment/dev | grep '^vault' --color=never
    delta: '0:00:00.004038'
    end: '2020-12-16 15:03:14.420361'
    failed: false
    rc: 0
    start: '2020-12-16 15:03:14.416323'
    stderr: ''
    stderr_lines: []
    stdout: vault_pass_user_foo
    stdout_lines:
    - vault_pass_user_foo

TASK [vault-scripts : Dump Vault Variables] *****************************************************************************************
ok: [localhost] => (item=vault_pass_user_foo) => 
  msg: |2-
  
    ---------
  
    vault_pass_user_foo: =+7qpEa4pJcGhgFwvJCElF3CddaTO2GhUg/Ex3FO6mnUk=
  
    ---------

PLAY RECAP **************************************************************************************************************************
localhost                  : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   


```

Note - this script works on the convention that all vaulted variables are root level yaml variables, not part of any
nested structure, and also that they are prefixed with `vault`. It is suggested that whilst this is a limitation, it is
not necessarily a bad style to have to conform to. If you need to encrypt things in a nested structure, you will need to
define them as a top level vaulted variable and then use that vaulted variable in your nested structure.

### ReKey Vault File

You might have heard that using `encrypt-string` means that you can't change your encryption password? Well this script
lets you do just that.

The process is basically to decrypt using the current key and then re-encrypt using the new key.

First thing to do is prepare a new secret file, for which you can use the script already described
under [Generate Vault Secret](#generate-vault-secret)

One you are ready to re-encrypt, it is strongly suggested that you have already commited your current state to allow
easy roll back

Then you can run a command like:

```bash
bash shellscripts/vault/rekeyVaultFile.bash \
  dev \
  ./vault-pass-dev.secret \
  dev \
  ./vault-pass-dev.secret-new \
  environment/dev/group_vars/all/vault-*
```

If you have one tier of subfolders in your group vars folder, you coudl do something like 
```bash
bash shellscripts/vault/rekeyVaultFile.bash dev ./vault-pass-old.secret dev ./vault-pass-new.secret ./environment/dev/group_vars/*/vault*
```

In the above, we are rekeying values in the `dev` environment, using the current secret file to read and the new secret
file to write

When the process runs, it does not overwrite the existing files, instead it makes new versions prefixed with `new_`

You can manually check these to confirm they are OK, and then when you are ready you might want to do something like:

```bash
# go to the folder where you have been rekeying
cd environment/dev/group_vars/all/

#remove old files
rm -f vault-*

#move new files into place
for f in new_vault-*; do mv "$f" "${f#new_}"; done
```

Another option if you have multiple sub folders in group vars, is something like
```
cd environment/dev/group_vars/; for d in *; do (cd $d; rm -f vault*; for f in new_*; do mv "$f" "${f#new_}"; done;) done
```
Once you are done, first of all you should rename your new secret file so that it is now the same as the secret file
yuou have configured in `ansible.cfg`.

Then you might want to [Dump Secrets](#dump-secrets) to confirm that everything is working as it should.

Finally remove your old key, you no longer need it.
