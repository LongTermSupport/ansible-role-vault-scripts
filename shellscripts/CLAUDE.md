# CLAUDE.md - Vault Secrets Management Guidelines

This document outlines the standards and conventions for the vault secrets management scripts in this directory. These scripts form a standalone library for managing encrypted secrets with Ansible Vault.

## File Path Handling

The scripts use several functions to handle file paths consistently:

1. `getFilePath(filePath)`: 
   - Accepts a file path and returns its absolute path using `realpath`
   - If the file exists at the provided path, returns that path
   - If the file exists at `projectDir/filePath`, returns that path
   - Otherwise, throws an error

2. `getFilePathOrEmptyString(filePath)`:
   - If input is empty, returns an empty string
   - Otherwise, calls `getFilePath` to get the absolute path

3. `getProjectFilePathCreateIfNotExists(filePath)`:
   - If input is empty, returns an empty string
   - If the path doesn't start with `projectDir`, prepends it
   - If the file exists, returns its absolute path
   - If the file doesn't exist, creates its parent directories and the file itself, then returns the absolute path

4. `validateOutputToFile(outputToFile, varname)`:
   - Validates that `outputToFile` is an absolute path (must start with `/`)
   - Checks if the variable is already defined in the output file
   - Ensures the output file's parent directory exists

In most scripts, `outputToFile` parameters are processed through one of these functions to ensure consistency. Output files are typically Ansible vault files in the environment directory structure.

## Coding Standards

### Parameter Order

All scripts should follow a consistent parameter order:

1. Required parameters first (varname, file path, etc.)
2. Optional parameters after required ones  
3. Environment parameter always as the last parameter, defaulting to "dev"

Standard parameter order examples:
```bash
# Create password or string scripts
./createVaultedPassword.bash [varname] [outputToFile] [specifiedEnv]
./createVaultedString.bash [varname] [string] [outputToFile] [specifiedEnv]

# Create key pair scripts
./createVaultedSshKeyPair.bash [varname_prefix] [email] [outputToFile] [specifiedEnv] [keepKeys]
```

For scripts requiring source and destination environments:
```bash
./copyVaultFileToEnvironment.bash [srcEnv] [destEnv] [vaultFilePaths...]
```

### Script Help Text

All scripts should have consistent help text formatting:

```
USAGE:

This script will [brief description of what it does]

Usage: ./$(basename $0) [param1] [param2] [optional: param3] [optional: specifiedEnv - defaults to $defaultEnv]

Please note, the varname must be prefixed with 'vault_'

Examples:
./$(basename $0) vault_example_var output/path.yml
```

### Environment Handling

All scripts that accept an environment parameter should:
- Place it as the last parameter
- Default to "dev" if not specified: `readonly specifiedEnv="${N:-$defaultEnv}"`
- Call `assertValidEnv` to validate it

Scripts now automatically detect the environment from the output file path:
- If the output file path contains `/environment/[env]/`, the script will use that environment
- If a specific environment parameter is provided that conflicts with the path, an error is shown
- The user is informed when an environment is auto-detected from the path
- This makes specifying the environment parameter unnecessary in most cases

For example, when running:
```bash
./createVaultedPassword.bash vault_db_password environment/prod/group_vars/containers/vault_passwords.yml
```
The script will automatically detect "prod" as the environment and use the corresponding vault password file.

### Variable Naming

- All vault variable names must be prefixed with `vault_`
- Use descriptive names that indicate the purpose of the secret
- Use snake_case for all variable names

### Validation Standards

All scripts should implement these validations consistently:
- Check that varnames begin with `vault_` using `assertPrefixedWithVault`
- Validate environment names with `assertValidEnv`
- Check file existence/permissions before operations
- Use `validateOutputToFile` to validate output file paths

### Error Handling

- Use `set -euo pipefail` for robust error handling
- Use the provided error reporting functions consistently
- Check for required tools before executing (ansible, openssl, etc.)

## Script Organization

### Core Scripts
- `_top.inc.bash` - Base setup for all scripts
- `_allEnv.top.inc.bash` - Setup for multi-environment scripts
- `_vault.inc.bash` - Vault-specific setup
- `_vault.functions.inc.bash` - Reusable vault functions

### Password and String Management
- `generatePassword.bash` - Create secure random passwords
- `createVaultedPassword.bash` - Generate and encrypt random passwords
- `createVaultedString.bash` - Encrypt specific string values
- `createVaultedPreSharedKey.bash` - Generate and encrypt PSKs

### SSH Key Management
- `createVaultedSshKeyPair.bash` - Create password-protected SSH keys
- `createVaultedSshDeployKeyPair.bash` - Create deployment SSH keys

### Multi-environment Tools
- `allEnvCreateVaultedPassword.bash` - Create same password across environments
- `allEnvCreateVaultedString.bash` - Encrypt same string across environments
- `allEnvCreateVaultedSshDeployKeyPair.bash` - Create keys across environments

### File Operations
- `createVaultedDataFromFile.bash` - Encrypt file contents as variables
- `createDeployKeysFromTemplate.bash` - Create keys from template file
- `createPasswordsFromTemplate.bash` - Create passwords from template file
- `rekeyVaultFile.bash` - Re-encrypt vault files with new password
- `copyVaultFileToEnvironment.bash` - Copy vault files between environments

### Viewing Tools
- `dumpGroupSecrets.bash` - Display decrypted secrets for groups
- `dumpSecretsInFiles.bash` - Display decrypted secrets from files

## Fixed Issues

### String Content Handling
- Added whitespace trimming for strings in createVaultedString.bash
- Added --preserve-whitespace flag to maintain leading/trailing whitespace
- Updated allEnvCreateVaultedString.bash to pass the flag to the underlying script
- Improved command-line option parsing

### Fixed Variable Handling
- Resolved issue with readonly variables in environment detection
- Created finalSpecifiedEnv variable to safely store the detected environment
- Updated all ansible-vault command calls to use finalSpecifiedEnv
- Ensured consistent environment handling across all scripts
- Added validation to abort when invalid environments are detected in file paths
- Improved error messages showing valid environment options

### Environment Auto-detection
- Added automatic environment detection from output file paths
- Scripts now check if the output file path contains `/environment/env/` and use that environment
- Users are informed when an environment is auto-detected
- Eliminated the need to specify both an environment path and environment parameter
- Added proper error handling for conflicting environment specifications

### Consistent Help Text
- Standardized all help text formatting across scripts
- Added detailed usage notes explaining the auto-detection feature
- Improved examples that accurately reflect parameter usage
- Added consistent formatting for optional parameters

### Parameter Handling
- Implemented consistent approach to environment parameter handling
- Used consistent variable names (userSpecifiedEnv and specifiedEnv)
- Centralized environment detection in _vault.functions.inc.bash

## Remaining Issues and Improvement Areas

### Updated Scripts
All scripts have been updated to use a consistent approach to environment handling:

Basic scripts with standard parameter order:
- `createVaultedPassword.bash` - Generate and encrypt a random password
- `createVaultedString.bash` - Encrypt a specific string (trims whitespace by default, use --preserve-whitespace to keep it)
- `createVaultedDataFromFile.bash` - Encrypt a file's contents
- `createVaultedSshDeployKeyPair.bash` - Create an SSH deploy key pair
- `createVaultedSshKeyPair.bash` - Create a password-protected SSH key pair
- `createVaultedPreSharedKey.bash` - Create a pre-shared key
- `createVaultedSslClientCertificateAndAuth.bash` - Create SSL client certificate

Scripts that operate across environments:
- `allEnvCreateVaultedPassword.bash` - Create password across all environments
- `allEnvCreateVaultedString.bash` - Create string across all environments
- `allEnvCreateVaultedSshDeployKeyPair.bash` - Create SSH keys across all environments

Template-based scripts:
- `createDeployKeysFromTemplate.bash` - Create keys based on a template file
- `createPasswordsFromTemplate.bash` - Create passwords based on a template file

Special purpose scripts:
- `copyVaultFileToEnvironment.bash` - Copy and rekey vault files between environments

### Special Cases
Some scripts have legitimately different parameter ordering due to their specialized functionality:
- `copyVaultFileToEnvironment.bash` - Takes source and destination environments as first parameters
- `rekeyVaultFile.bash` - Takes source and destination key files as parameters
- The allEnv* scripts - Have a different parameter structure for working across environments

### Potential Future Improvements
- Add unit tests to verify script behavior
- Create a comprehensive test suite for all scripts
- Add a script to verify the integrity of all vault files
- Implement better error messages with debugging information
- Consider adding a --verbose flag to show more detailed output
- Add option to generate different password styles (words, numeric, etc.)
- Implement a way to update existing keys without recreating them
- Add a mechanism to rotate keys on a schedule

## Environments

The vault scripts support multiple environments:
- `dev` - Default environment for development
- `prod` - Production environment
- `localdev` - Local development environment
- `untrusted` - Environment for untrusted services

Each environment uses a corresponding vault password file (`vault-pass-{env}.secret`).

## Recommendations

1. Standardize parameter order across all scripts
2. Update help text to match actual implementation
3. Ensure environment parameter is consistently the last parameter
4. Implement consistent validation patterns
5. Document each script's purpose and parameters clearly
6. Add comments for complex operations
7. Create a test suite for script validation