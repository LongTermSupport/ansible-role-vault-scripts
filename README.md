# Ansible Role: Vault Scripts

Shell scripts for managing secrets with **Ansible Vault encrypted strings** (`ansible-vault encrypt_string` / `!vault |`). Generate vaulted passwords, SSH key pairs, SSL client certificates, rekey encrypted strings, and dump secrets — all from simple Bash commands.

Packaged as an Ansible role for easy version-pinning via `requirements.yml`.

## Why Vault Strings?

Ansible Vault offers two encryption approaches: encrypting entire files, or encrypting individual variable values (vault strings). Vault strings are the better workflow for most teams because:

- **Variable names stay in plaintext** — you can `grep` for `db_password` across your entire codebase
- **Values are never decrypted during development** — no risky decrypt/edit/re-encrypt cycle
- **Git diffs show which variable changed** — not a meaningless blob of ciphertext
- **AI coding assistants can reason about your infrastructure** — they see the structure without seeing secrets
- **Code reviews actually work** — reviewers see the key name that changed, even in GitHub/GitLab PRs

The common objection is that `ansible-vault rekey` does not work with encrypted strings. This role solves that with `rekeyVaultFile.bash`.

For a detailed comparison, see [Stop Encrypting Entire Files with Ansible Vault](https://ltscommerce.dev/articles/ansible-vault-strings-vs-file-encryption).

## Installation

Add to your `requirements.yml`:

```yaml
- src: https://github.com/LongTermSupport/ansible-role-vault-scripts
  scm: git
  name: lts.vault-scripts
  version: master
```

Install with Ansible Galaxy:

```bash
ansible-galaxy install \
    --force \
    --keep-scm-meta \
    --role-file=requirements.yml \
    --roles-path=roles
```

Symlink the scripts into your project:

```bash
mkdir -p shellscripts
ln -s ../roles/lts.vault-scripts/shellscripts/ shellscripts/vault
```

## Prerequisites

- `ansible-vault` (comes with Ansible)
- `yq` ([mikefarah/yq](https://github.com/mikefarah/yq)) for YAML parsing
- `ansible.cfg` in your project root
- An environment directory structure, e.g. `environment/dev/`, `environment/prod/`
- `*.secret` in your `.gitignore` (vault password files must never be committed)

## Quick Start

```bash
# 1. Generate a vault password file
bash shellscripts/vault/generateVaultSecret.bash dev

# 2. Create an encrypted password variable
bash shellscripts/vault/createVaultedPassword.bash \
    vault_db_password \
    ./environment/dev/group_vars/all/vault_database.yml

# 3. View your secrets
bash shellscripts/vault/dumpGroupSecrets.bash dev
```

## Scripts Reference

Every script prints usage instructions when run without arguments.

### Environment Handling

All scripts accept an optional environment parameter (defaults to `dev`). Scripts auto-detect the environment from output file paths — if the path contains `/environment/prod/`, the script uses `prod` automatically.

You can also set a session default:

```bash
export vaultScriptsDefaultEnv=prod
```

### Secret Generation

| Script | Purpose |
|--------|---------|
| `generateVaultSecret.bash` | Generate a vault password file with cryptographically random content |
| `generatePassword.bash` | Generate a random password string |

### Password and String Encryption

| Script | Purpose |
|--------|---------|
| `createVaultedPassword.bash` | Generate a random password, encrypt it, assign to a variable |
| `createVaultedString.bash` | Encrypt a specific string value and assign to a variable |
| `createVaultedPreSharedKey.bash` | Generate and encrypt a pre-shared key |

**Examples:**

```bash
# Generate and encrypt a random password, write to file
bash shellscripts/vault/createVaultedPassword.bash \
    vault_db_password \
    ./environment/prod/group_vars/all/vault_database.yml

# Encrypt a specific string, output to stdout
bash shellscripts/vault/createVaultedString.bash \
    vault_api_key \
    "sk-live-abc123def456"

# Generate a shorter password
bash shellscripts/vault/createVaultedString.bash \
    vault_short_pass \
    "$(bash shellscripts/vault/generatePassword.bash 20)"
```

### SSH Key Management

| Script | Purpose |
|--------|---------|
| `createVaultedSshKeyPair.bash` | Create a password-protected SSH key pair (passphrase + private + public, all encrypted) |
| `createVaultedSshDeployKeyPair.bash` | Create a passwordless SSH key pair for read-only deploy access |

**Examples:**

```bash
# Password-protected SSH key pair
bash shellscripts/vault/createVaultedSshKeyPair.bash \
    vault_deploy \
    ops@example.com \
    ./environment/prod/group_vars/all/vault_ssh_keys.yml

# Deploy key (no passphrase — use only for read-only deploy keys)
bash shellscripts/vault/createVaultedSshDeployKeyPair.bash \
    vault_github_deploy \
    ops@example.com \
    ./environment/prod/group_vars/all/vault_ssh_keys.yml
```

The SSH key pair script generates three variables:

```yaml
vault_deploy_id_passphrase: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  ...
vault_deploy_id: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  ...
vault_deploy_id_pub: !vault |
  $ANSIBLE_VAULT;1.2;AES256;dev
  ...
```

### SSL Client Certificates

| Script | Purpose |
|--------|---------|
| `createVaultedSslClientCertificateAndAuth.bash` | Generate a CA and client certificate for mutual TLS authentication |

```bash
bash shellscripts/vault/createVaultedSslClientCertificateAndAuth.bash \
    vault_client_foo \
    '/C=GB/ST=England/L=London/O=Example Ltd/CN=Example Ltd/emailAddress=info@example.com' \
    ./environment/prod/group_vars/all/vault_client_certs.yml \
    prod
```

Use with Nginx:

```nginx
ssl_client_certificate /path/to/ca.cert;
ssl_verify_client on;
```

### Multi-Environment Operations

| Script | Purpose |
|--------|---------|
| `allEnvCreateVaultedPassword.bash` | Create the same password across all environments |
| `allEnvCreateVaultedString.bash` | Encrypt the same string across all environments |
| `allEnvCreateVaultedSshDeployKeyPair.bash` | Create SSH deploy keys across all environments |

### Template-Based Bulk Creation

| Script | Purpose |
|--------|---------|
| `createPasswordsFromTemplate.bash` | Generate passwords for all variables listed in a template file |
| `createDeployKeysFromTemplate.bash` | Generate deploy keys for all entries listed in a template file |

### Viewing Secrets

| Script | Purpose |
|--------|---------|
| `dumpGroupSecrets.bash` | Display decrypted group_vars secrets |
| `dumpSecretsInFiles.bash` | Display decrypted secrets from arbitrary files (host_vars, etc.) |

```bash
# View all group_vars secrets for dev
bash shellscripts/vault/dumpGroupSecrets.bash dev

# View a single secret
bash shellscripts/vault/dumpGroupSecrets.bash dev vault_db_password

# Dump secrets from specific files
bash shellscripts/vault/dumpSecretsInFiles.bash dev environment/dev/host_vars/*.yml
```

### Rekeying (Password Rotation)

The `rekeyVaultFile.bash` script solves the "you cannot rekey encrypted strings" limitation. It decrypts each variable with the old key and re-encrypts with the new key.

```bash
# 1. Generate a new vault password file
bash shellscripts/vault/generateVaultSecret.bash dev
# Rename the new file, e.g. vault-pass-dev.secret-new

# 2. Rekey all vault files
bash shellscripts/vault/rekeyVaultFile.bash \
    dev \
    ./vault-pass-dev.secret \
    dev \
    ./vault-pass-dev.secret-new \
    environment/dev/group_vars/all/vault-*

# 3. Review the new_* prefixed files, then replace originals
cd environment/dev/group_vars/all/
rm -f vault-*
for f in new_vault-*; do mv "$f" "${f#new_}"; done

# 4. Replace the old secret file with the new one
# 5. Verify with dumpGroupSecrets.bash
```

### Copying Secrets Between Environments

```bash
# Copy vault files from prod to dev (rekeys with the destination environment's password)
bash shellscripts/vault/copyVaultFileToEnvironment.bash \
    prod \
    dev \
    ./environment/prod/group_vars/all/vault_client_certs.yml
```

## Project-Level Configuration

You can override the role's default settings on a per-project basis by creating a `vaultScriptsSettings.inc.bash` file
in your project root (the directory containing `ansible.cfg`).

This file is sourced **after** the role's own `vaultScriptsSettings.inc.bash`, so any variables you set will override
the role defaults. This allows you to customise environment names, default email addresses, and other settings without
modifying the role itself.

Example `vaultScriptsSettings.inc.bash` in your project root:

```bash
#!/usr/bin/env bash
# Project-specific vault scripts configuration

# Override default environments (role default: dev prod localdev untrusted)
export VAULT_SCRIPTS_ENVIRONMENTS="staging production"

# Override default email for deploy keys
export VAULT_SCRIPTS_DEFAULT_EMAIL="ops@example.com"

# Override default environment (role default: dev)
export vaultScriptsDefaultEnv="staging"
```

Available settings (see the role's `shellscripts/vaultScriptsSettings.inc.bash` for the full list):

| Variable | Default | Description |
|----------|---------|-------------|
| `VAULT_SCRIPTS_ENVIRONMENTS` | `dev prod localdev untrusted` | Space-separated list of valid environment names |
| `VAULT_SCRIPTS_DEFAULT_EMAIL` | (none) | Default email address for deploy key generation |
| `VAULT_SCRIPTS_SKIP_EXISTING` | `true` | Skip existing keys without error (`true`) or fail (`false`) |
| `vaultScriptsDefaultEnv` | `dev` | Default environment when none is specified |

## Conventions

- All vaulted variable names **must** be prefixed with `vault_`
- Vaulted variables must be **top-level YAML keys** (not nested)
- Vault password files use the naming pattern `vault-pass-{env}.secret`
- The `*.secret` glob should be in your `.gitignore`

These constraints are intentional — they make secrets easily identifiable, greppable, and compatible with the dump/rekey tooling.

## Supported Environments

The default environment is `dev`. Common environments:

- `dev` — local/shared development
- `staging` — pre-production
- `prod` — production
- `localdev` — individual developer machines

Each environment uses its own vault password file (`vault-pass-{env}.secret`).

## Licence

Apache License 2.0. See [LICENSE](LICENSE).
