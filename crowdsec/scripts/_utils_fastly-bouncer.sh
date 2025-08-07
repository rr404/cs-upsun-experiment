#!/bin/sh
#shellcheck disable=SC3043

set -eu

# Source generic utilities
# shellcheck source=./_utils.sh
. "$(dirname "$0")/_utils.sh"

BOUNCER="crowdsec-fastly-bouncer"
BOUNCER_PREFIX=$(echo "$BOUNCER" | sed 's/crowdsec-/cs-/g')

# This is a library of Fastly bouncer-specific functions that can be
# sourced by installation scripts.
#
# While not requiring bash, it is not strictly POSIX-compliant because
# it uses local variables, but it should work with every modern shell.
#
# Since passing/parsing arguments in posix sh is tricky, we share
# some environment variables with the functions. It's a matter of
# readability balance between shorter vs cleaner code.

# Use environment-specific paths for non-sudo /app/cs environment
# shellcheck disable=SC2034
{
SERVICE="$BOUNCER.service"
SERVICE_MODE="${SERVICE_MODE:-user}"
# Fastly bouncer uses Python/pip installation, so no binary path needed
CONFIG_DIR="${CONFIG_DIR:-${CROWDSEC_DIR:-/app/cs/etc/crowdsec}/bouncers}"
BOUNCER_CONFIG_FILE="$BOUNCER.yaml"
BOUNCER_CONFIG_FILE_FULL_PATH="$CONFIG_DIR/$BOUNCER_CONFIG_FILE"
# Use user systemd path instead of system
SYSTEMD_PATH_FILE="${SYSTEMD_PATH_FILE:-$HOME/.config/systemd/user/$SERVICE}"
# Python virtual environment path
VENV_PATH="${VENV_PATH:-${CROWDSEC_DIR:-/app/cs/etc/crowdsec}/venv}"
}

# Check if pip and python are available
check_python_requirements() {
    if ! command -v python3 >/dev/null; then
        msg err "python3 is required but not found"
        return 1
    fi
    
    if ! command -v pip3 >/dev/null && ! python3 -m pip --version >/dev/null 2>&1; then
        msg err "pip3 is required but not found"
        return 1
    fi
    
    return 0
}

# Setup Python virtual environment
setup_python_venv() {
    require 'VENV_PATH'
    
    if [ ! -d "$VENV_PATH" ]; then
        msg info "Creating Python virtual environment at $VENV_PATH"
        python3 -m venv "$VENV_PATH" || {
            msg err "Failed to create virtual environment"
            return 1
        }
    fi
    
    # Activate virtual environment
    # shellcheck source=/dev/null
    . "$VENV_PATH/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip >/dev/null 2>&1 || {
        msg warn "Failed to upgrade pip"
    }
    
    return 0
}

# Install Fastly bouncer via pip
install_fastly_bouncer() {
    require 'VENV_PATH'
    
    # Activate virtual environment
    # shellcheck source=/dev/null
    . "$VENV_PATH/bin/activate"
    
    msg info "Installing crowdsec-fastly-bouncer via pip..."
    if pip install crowdsec-fastly-bouncer >/dev/null 2>&1; then
        msg succ "Fastly bouncer installed successfully"
        return 0
    else
        msg err "Failed to install crowdsec-fastly-bouncer"
        return 1
    fi
}

# Generate Fastly bouncer configuration
generate_fastly_config() {
    require 'BOUNCER_CONFIG_FILE_FULL_PATH' 'VENV_PATH'
    local fastly_tokens
    
    fastly_tokens="${FASTLY_API_TOKEN:-}"
    if [ -z "$fastly_tokens" ]; then
        msg warn "FASTLY_API_TOKEN not set - will generate basic config"
        fastly_tokens="<FASTLY_TOKEN>"
    fi
    
    # Activate virtual environment
    # shellcheck source=/dev/null
    . "$VENV_PATH/bin/activate"
    
    # Create config directory
    mkdir -p "$(dirname "$BOUNCER_CONFIG_FILE_FULL_PATH")"
    
    msg info "Generating Fastly bouncer configuration..."
    if [ "$fastly_tokens" = "<FASTLY_TOKEN>" ]; then
        # Generate basic config without tokens
        crowdsec-fastly-bouncer -g "$fastly_tokens" > "$BOUNCER_CONFIG_FILE_FULL_PATH" 2>/dev/null || {
            msg err "Failed to generate configuration"
            return 1
        }
    else
        # Generate config with actual tokens
        crowdsec-fastly-bouncer -g "$fastly_tokens" > "$BOUNCER_CONFIG_FILE_FULL_PATH" 2>/dev/null || {
            msg err "Failed to generate configuration with tokens"
            return 1
        }
    fi
    
    chmod 0600 "$BOUNCER_CONFIG_FILE_FULL_PATH"
    msg succ "Configuration file created: $BOUNCER_CONFIG_FILE_FULL_PATH"
    return 0
}

# Set API key in the Fastly bouncer config
set_fastly_api_key() {
    require 'BOUNCER_CONFIG_FILE_FULL_PATH'
    local api_key ret
    ret=0

    # Use the generic bouncer registration function
    if api_key=$(register_bouncer); then
        msg succ "API Key successfully created for Fastly bouncer"
        # API_KEY is already exported by register_bouncer
    else
        msg err "Failed to register bouncer with CrowdSec"
        api_key="<API_KEY>"
        ret=1
    fi

    if [ "$api_key" != "" ] && [ "$api_key" != "<API_KEY>" ]; then
        # Update lapi_key in the YAML config
        if command -v sed >/dev/null; then
            sed -i "s/<API_KEY>/$api_key/g" "$BOUNCER_CONFIG_FILE_FULL_PATH"
            sed -i "s/lapi_key:.*/lapi_key: $api_key/" "$BOUNCER_CONFIG_FILE_FULL_PATH"
        fi
    fi

    return "$ret"
}

# Set local LAPI URL in Fastly config
set_fastly_lapi_url() {
    require 'BOUNCER_CONFIG_FILE_FULL_PATH'
    local port cscli_cmd
    
    cscli_cmd="${CROWDSEC_DIR:-/app/cs/etc/crowdsec}/cscli"
    if [ ! -x "$cscli_cmd" ]; then
        cscli_cmd="cscli"
    fi
    
    command -v "$cscli_cmd" >/dev/null || return 0

    if [ -n "${CROWDSEC_DIR:-}" ] && [ -f "${CROWDSEC_DIR}/config.yaml" ]; then
        port=$("$cscli_cmd" --config "${CROWDSEC_DIR}/config.yaml" config show -oraw --key "Config.API.Server.ListenURI" 2>/dev/null | cut -d ":" -f2 || true)
    else
        port=$("$cscli_cmd" config show -oraw --key "Config.API.Server.ListenURI" 2>/dev/null | cut -d ":" -f2 || true)
    fi
    
    if [ "$port" = "" ]; then
        port=8080
    fi

    # Update lapi_url in the YAML config
    if command -v sed >/dev/null; then
        sed -i "s|lapi_url:.*|lapi_url: http://127.0.0.1:$port|" "$BOUNCER_CONFIG_FILE_FULL_PATH"
        sed -i "s|url:.*|url: http://127.0.0.1:$port|" "$BOUNCER_CONFIG_FILE_FULL_PATH"
    fi
}

# Test Fastly bouncer configuration
test_fastly_config() {
    require 'BOUNCER_CONFIG_FILE_FULL_PATH' 'VENV_PATH'
    
    # Activate virtual environment
    # shellcheck source=/dev/null
    . "$VENV_PATH/bin/activate"
    
    if [ -f "$BOUNCER_CONFIG_FILE_FULL_PATH" ]; then
        msg info "Testing Fastly bouncer configuration..."
        if crowdsec-fastly-bouncer -c "$BOUNCER_CONFIG_FILE_FULL_PATH" -t >/dev/null 2>&1; then
            msg succ "Configuration test successful"
            return 0
        else
            msg warn "Configuration test failed - check $BOUNCER_CONFIG_FILE_FULL_PATH manually"
            return 1
        fi
    else
        msg err "Configuration file not found: $BOUNCER_CONFIG_FILE_FULL_PATH"
        return 1
    fi
}

# Delete Fastly bouncer - use generic function
# This function is now provided by the generic _utils.sh
# Call: delete_bouncer [bouncer_name]