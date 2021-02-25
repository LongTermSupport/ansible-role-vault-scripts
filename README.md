# Vault Scripts

This role is primarly a container for some utility shell scripts to assist with working Ansible vault, specifically using encrypt-string

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

## Limitations

* vaulted variables must be prefixed with `vault_`
* vaulted variables must be top level variables, not part of any nested structure. 

It is suggested that whilst these are limitations, it is not necessarily a bad style to have to conform to. If you need to encrypt things in a nested structure, you will need to define them as a top level vaulted variable and then use that vaulted variable in your nested structure.

## Instructions for Scripts

For each script, execute without arguments to get usage instructions

### Generate Vault Secret

This script will generate a secret file for you with a good long chunk of random text

```bash
bash shellscripts/vault/generateVaultSecret.bash dev
```
eg `vault-pass-dev.secret`
```
85E88clxKzfNtC/Hdh4vKD5GMdY0vbbBPq/9zQJvWD2XSg/g+sv+wSlFXbgPGG2B502/MXV0DvUI1kbcKw+w2IX2knIeZdhw7LSRT8yXBuQQxCkbrfsZaxH/avljFMgdds/bmL/aFedkFMhngLn0xXGlcGgxukr7jv5uBZx/B4kMK92kO9xpOBuRa/I8cs5bY777ZWuS009ZN4WJVXByDe49lLj29FmtXy64A+XsaOzvrM9YM7K5kURfDF0woQV1zjR
+lMRf/FLKBRdCJ1L1YhKKlBUMPK9kpNPbj1mq5eZ33nqKGEywNaBwJO8T/Jhe/4BPJIa2kyDZFU0kzWKWv+90FfDxUchpeOghzXdWjPJBGXGvyS6Pe/c8t+RTTduMge/rBO7ANziPXSQOT3271KnF7sgaHzWjU9t3/GXRx+bJ/s3/Tgjz9suLtuKJwI/gaPAWx2DABa6/ggXI8F+qdQomdFQ6hyJWPVYpLdcedm6/SMC80Io9He+94VD02Whl74bqS0/+JF/k5zVUyunGcbR2jRmYpixTwnuve5RPDZ6WgoSwbEblXtqpm34U2C35IEz71gOImPax5qrNylnv8iY7GxIu1ryO1x0JZ
yO5oVDAsRwF/aISUeqj5h2wg/L2829MnRONmQ7NIz5adYsabsb8hAON9nzhHdgQ6CbnKtgpe5OwzqmwPb4E1zgNpoXd1vZfzd+EfP1YvBK/uQjuIE6p5jYX/gIzYn+4dfrUVtjX1pHs7XSGKGEnZ6L32+APZwMmTpA2T6GoqLi+9RYmsAQtygSHGuyuCeYDz5Dg2wbygWLhItZSW6gt7zSc6+MYL6m4rHcUXJxMAv5sI3MmTUQZEfjBxRr3BYjSaygCn6LaI4M5aMdQ/ikyleh/5Ts/TvFatsc5LAxVwRLpaSfs8kKYfqeRUBhx8ImM6pOrZOvOPzpyKDehl7hzdMPTxAqbgEsm5B+xs8+UTL7Ztcmtqc6iGGU+4yuDNzR/tjadyZQiP+mOg5RZV
uva18Gg9VRrd9vDSugsm2389lhWx5Dwx5y1W8yKKBDAASYKeCgDrxtqYonW0grz0LrnBOrU1zXKHtdEhsMbzpXDU3nKHF2PDIHxupVXtzXrVPecOsJ2UrrBhLu29H4r68yq5k
```

You can pass a second `update` argument if you want to overwrite an existing file, but of course be careful with that

You should ensure your secret files are NOT tracked by git and are never committed. Instead you MUST make sure you note down the secret file contents wherever you manage secrets, eg a password manager or other secure secrets storage system

(Note - Ansible 2.10 allows storing multiple keys in a single file prefixed with the key ID, however for the sake of backwards compat, we use a separate file for each key. You could choose to consolidate these into a single file if you are using 2.10 or greater)

### Create Vaulted Password

This script will generate as password string and then encrypt it for you, generating yaml that assigns the encrrypt password to the specified variable

For example, in the `dev` environment, generate a password and vault it, then write it to the file `./environment/dev/vault_user_passwords.yml` assigned to the variable `vault_pass_user_foo`

```bash

bash shellscripts/vault/createVaultedPassword.bash dev vault_pass_user_foo ./environment/dev/group_vars/all/vault_user_passwords.yml

```

As above, but instead of writing to file, just write to stdout so that you can copy paste it manually where ever you want
```bash

bash shellscripts/vault/createVaultedPassword.bash dev vault_pass_user_foo

```

### Create Vaulted String - eg Encrypt Specific Password or Other Secret

If you need to encrypt a password that is predefined or has specific requirements not met by the auto generated password created with createVaultedPassword.bash then you can use this script

For example, if we need a shorter password than the standard one:

```bash
bash shellscripts/vault/createVaultedString.bash prod vault_pass_user_foo "$(bash shellscripts/vault/generatePassword.bash 20)"
```

### Create Vaulted SSH Key Pair

This script will generate password protected private and public keys, encrypt them as strings and then assign the passphrase and the public/private key to variables that are prefixed with teh prefix you specify. Finally this can optionally be written directly to the file you specify as normal

For example

```bash

# echo to stdout
bash shellscripts/vault/createVaultedSshKeyPair.bash dev vault_default ops@domain.com

# write directly to file
bash shellscripts/vault/createVaultedSshKeyPair.bash dev vault_default ops@domain.com ./environment/dev/group_vars/all/vault_ssh_keys.yml

```

Will generate the following variables (truncated for readability):

```yaml

vault_default_id_rsa_passphrase: !vault |
          $ANSIBLE_VAULT;1.2;AES256;dev
          37383634643132346565376332663265363435316431323236626561626263373965366230313035 (...)
vault_default_id_rsa: !vault |
          $ANSIBLE_VAULT;1.2;AES256;dev
          63373964336530653133336565306533626165646338633061636363666132363731656632636435 (...)
vault_default_id_rsa_pub: !vault |
          $ANSIBLE_VAULT;1.2;AES256;dev
          37666166393434346539356139393432636134633239643531623761396333323761313435663136 (...)


```


### Dump Secrets

Once you have some secrets stored in an environment folder, you will probably want a way to easily view them

For this, you can use this script

For example, to view all secrets in the dev environment

```bash
bash shellscripts/vault/dumpSecrets.bash dev
```

Example output:

```
bash shellscripts/vault/dumpSecrets.bash dev

===========================================
 shellscripts/vault/dumpSecrets.bash dev
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

Note - this script works on the convention that all vaulted variables are root level yaml variables, not part of any nested structure, and also that they are prefixed with `vault`. It is suggested that whilst this is a limitation, it is not necessarily a bad style to have to conform to. If you need to encrypt things in a nested structure, you will need to define them as a top level vaulted variable and then use that vaulted variable in your nested structure.

### ReKey Vault File

You might have heard that using `encrypt-string` means that you can't change your encryption password? Well this 
script lets you do just that.

The process is basically to decrypt using the current key and then re-encrypt using the new key. 

First thing to do is prepare a new secret file, for which you can use the script already described under [Generate 
Vault Secret](#generate-vault-secret)

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

In the above, we are rekeying values in the `dev` environment, using the current secret file to read and the new 
secret file to write

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

And once you are done, you might want to [Dump Secrets](#dump-secrets) to confirm that everything is working as it 
should