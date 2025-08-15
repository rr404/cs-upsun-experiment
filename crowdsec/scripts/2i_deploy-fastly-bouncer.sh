#!/usr/bin/env bash

# Set variables for the bouncer installation
BOUNCER_FULL_NAME="crowdsec-fastly-bouncer"

BOUNCER_CONFIG="$BOUNCER_FULL_NAME.yaml"
BOUNCER_CONFIG_FULL_PATH="$CROWDSEC_DIR/bouncers/$BOUNCER_CONFIG"

# Python virtual environment path
VENV_PATH="${VENV_PATH:-${VAR_DIR}/pyvenv}"


#==========================================================================#

# Pre-requisites sourcing and variables setup
## Source the environment variables first
if [ -f "${PLATFORM_APP_DIR}/.environment" ]; then
    source "${PLATFORM_APP_DIR}/.environment"
fi

## Ensure TMP_DIR is available for the script
if [ -z "${TMP_DIR:-}" ]; then
    TMP_DIR="/tmp"
fi

## Source utils function functions
CROWDSEC_UTILS_SCRIPT="$(dirname "$0")/_utils.sh"
source "$CROWDSEC_UTILS_SCRIPT" || {
    echo "Error: Could not source CrowdSec utils script: $CROWDSEC_UTILS_SCRIPT"
    exit 1
}

#==========================================================================#

# Main deployment flow
main() {
    msg info "Starting Fastly bouncer deployment"  
    setup_python_environment
    install_and_setup_bouncer
        
    # Test configuration
    if test_fastly_bouncer_config; then
        msg succ "Fastly bouncer deployed successfully!"
        return 0
    else
        msg warn "Deployment completed with warnings"
        return 1
    fi
    
    # Show deployment summary
    show_deployment_summary
}

# Setup Python virtual environment for Fastly bouncer
setup_python_environment() {
    msg info "=== Setting up Python environment ==="
    
    # Check Python requirements
    if ! command -v python3 >/dev/null; then
        msg err "python3 is required but not found"
        exit 1
    fi
    
    # Create virtual environment
    if [ ! -d "$VENV_PATH" ]; then
        msg info "Creating Python virtual environment at $VENV_PATH"
        python3 -m venv "$VENV_PATH" || {
            msg err "Failed to create virtual environment"
            exit 1
        }
    fi
    
     # Verify pip is available (should be installed during build phase)
    if ! "$VENV_PATH/bin/pip" --version >/dev/null 2>&1; then
        msg err "pip is required but not found (should be installed during build)"
        exit 1
    fi

    msg succ "Python environment setup completed"
}

# Install Fastly bouncer via pip run config and link to LAPI
install_and_setup_bouncer() {
    msg info "=== Installing Fastly bouncer package ==="
    
    # Validate we have write access
    assert_can_write_to_path "$VENV_PATH/bin/crowdsec-fastly-bouncer"
    
    # Activate virtual environment and install bouncer
    msg info "Installing crowdsec-fastly-bouncer via pip..."
    # shellcheck source=/dev/null
    . "$VENV_PATH/bin/activate"
    
    # Upgrade pip first
    "$VENV_PATH/bin/pip" install --upgrade pip >/dev/null 2>&1 || msg warn "Failed to upgrade pip"

    # Install the bouncer
    if "$VENV_PATH/bin/pip" install crowdsec-fastly-bouncer >/dev/null 2>&1; then
        msg succ "Fastly bouncer installed successfully"
    else
        msg err "Failed to install crowdsec-fastly-bouncer"
        exit 1
    fi
    
    # Move Fastly bouncer to its the bin directory
    msg info "Moving Fastly bouncer to bin directory..."
    mv "$VENV_PATH/bin/crowdsec-fastly-bouncer" "$BIN_DIR/"

    # Copy the bouncer template configuration file if it exists
    msg info "Setting up bouncer configuration file..."
    assert_can_write_to_path "$BOUNCER_CONFIG_FULL_PATH"
    
    # Generate basic config using the bouncer's -g flag
    local fastly_tokens="${FASTLY_API_TOKENS:-<FASTLY_TOKEN>}"
    mkdir -p "$(dirname "$BOUNCER_CONFIG_FULL_PATH")"

    if "$BIN_DIR/crowdsec-fastly-bouncer" -g "$fastly_tokens" -c -o "$BOUNCER_CONFIG_FULL_PATH" 2>/dev/null; then
        chmod 0600 "$BOUNCER_CONFIG_FULL_PATH"
        msg succ "Configuration file created: $BOUNCER_CONFIG_FULL_PATH"
    else
        msg err "Failed to generate configuration file"
        exit 1
    fi
    
    # Retrieve LAPI url from CrowdSec config and save it to bouncer config
    msg info "Setting LAPI URL in bouncer configuration..."
    CROWDSEC_LAPI_URL=$(get_param_value_from_yaml "${CROWDSEC_DIR}/config.yaml" "api.server.listen_uri")
    set_config_var_value "$BOUNCER_CONFIG_FULL_PATH" 'CROWDSEC_LAPI_URL' "http://${CROWDSEC_LAPI_URL}"
    
    # Link bouncer to LAPI & update it's config with generated bouncer LAPI token
    msg info "Linking bouncer to LAPI and updating configuration..."
    link_bouncer_to_lapi "$BOUNCER_CONFIG_FULL_PATH" "$BOUNCER_FULL_NAME"
    msg info "Bouncer linked to LAPI"

    msg info "Fastly API tokens: Configured"
    # Update config with actual tokens (replace placeholder)
    set_config_var_value "$BOUNCER_CONFIG_FULL_PATH" 'FASTLY_TOKEN' "$FASTLY_API_TOKENS"
    msg succ "Fastly tokens configured in bouncer"

}

# Test Fastly bouncer configuration
test_fastly_bouncer_config() {
    msg info "=== Testing final configuration ==="
        
    if [ -f "$BOUNCER_CONFIG_FULL_PATH" ]; then
        msg info "Testing Fastly bouncer configuration..."
        if crowdsec-fastly-bouncer -c "$BOUNCER_CONFIG_FULL_PATH" -t >/dev/null 2>&1; then
            msg succ "Configuration test successful"
            return 0
        else
            msg warn "Configuration test failed - check $BOUNCER_CONFIG_FULL_PATH manually"
            msg info "You can test manually with: crowdsec-fastly-bouncer -c $BOUNCER_CONFIG_FULL_PATH -t"
            return 1
        fi
    else
        msg err "Configuration file not found: $BOUNCER_CONFIG_FULL_PATH"
        return 1
    fi
}

show_deployment_summary() {
    msg info "=== Deployment Summary ==="
    msg info "Configuration file: $BOUNCER_CONFIG_FULL_PATH"
    msg info "Bouncer: crowdsec-fastly-bouncer (installed via pip)"
    
    if [ -n "${FASTLY_API_TOKENS:-}" ]; then
        msg info "Fastly tokens: Configured"
    else
        msg warn "Fastly tokens: Not configured"
    fi
    
    msg info "To run the bouncer manually:"
    msg info "  $BIN_DIR/crowdsec-fastly-bouncer -c $BOUNCER_CONFIG_FULL_PATH"
}

#==========================================================================#

# Execute main deployment
main "$@"