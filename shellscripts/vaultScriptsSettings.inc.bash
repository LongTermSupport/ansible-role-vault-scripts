#!/usr/bin/env bash
# vaultScriptsSettings.inc.bash - Project-specific vault scripts configuration
# This file is sourced by _top.inc.bash to provide project-specific overrides

# Environments to use for allEnv scripts
# Default would be: dev prod localdev untrusted
# For this project, we exclude 'untrusted' as it has special handling
export VAULT_SCRIPTS_ENVIRONMENTS="dev prod localdev"

# Default behavior for existing keys
# true = skip existing keys without error (default)
# false = fail if key exists (old behavior)
export VAULT_SCRIPTS_SKIP_EXISTING=${VAULT_SCRIPTS_SKIP_EXISTING:-true}

# Project-specific default email for deploy keys
export VAULT_SCRIPTS_DEFAULT_EMAIL="joseph@ballicom.co.uk"

# Enable verbose output for debugging
# export VAULT_SCRIPTS_VERBOSE=${VAULT_SCRIPTS_VERBOSE:-false}

# Note: This file is optional. Scripts will work without it using defaults.