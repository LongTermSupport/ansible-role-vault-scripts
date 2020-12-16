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
