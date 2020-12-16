# Vault Scripts

This role is primarly a container for some utility shell scripts to assist with working Ansible vault, specifically using encrypt-string

These have been packaged as a role to assist with integrating these with your ansible projects

To install this into your project, first you need to add the following to your `requirements.yml` file:

```yaml
# Vault Script
 - src: https://github.com/LongTermSupport/ansible-role-vault-scripts
   scm: git
   name: vault-scripts                                                                                                            
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
ln -s ../{{ roles_path }}/vault-scripts/shellscripts/ vault
```
## Prerequisites

You must have the following set up for these to work:

* scripts installed to `shellscripts/vault` or otherwise a subdirectory 2 deep from your project root
* `ansible.cfg` file in the root of your project
* `environment/dev` folder containing your default dev environment (or whichever env name you choose to use)
* You have the line `*.secret` in your project `.gitignore` file

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

### Create Vaulted Password

This script will generate as password string and then encrypt it for you, generating yaml that assigns the encrrypt password to the specified variable

For example, in the `dev` environment, generate a password and vault it, then write it to the file `./environment/dev/vault_user_passwords.yml` assigned to the variable `vault_pass_user_foo`

```bash

bash shellscripts/vault/createVaultedPassword.bash dev vault_pass_user_foo ./environment/dev/vault_user_passwords.yml

```

As above, but instead of writing to file, just write to stdout so that you can copy paste it manually where ever you want
```bash

bash shellscripts/vault/createVaultedPassword.bash dev vault_pass_user_foo

```





