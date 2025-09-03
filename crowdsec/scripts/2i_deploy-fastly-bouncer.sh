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
    
    start_fastly_bouncer

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
        
    # Upgrade pip first
    "$VENV_PATH/bin/pip" install --upgrade pip >/dev/null 2>&1 || msg warn "Failed to upgrade pip"

    # Install the bouncer
    if "$VENV_PATH/bin/pip" install crowdsec-fastly-bouncer >/dev/null 2>&1; then
        msg succ "Fastly bouncer installed successfully"
    else
        msg err "Failed to install crowdsec-fastly-bouncer"
        exit 1
    fi
    
    # Copy Fastly bouncer to its the bin directory
    msg info "Copying Fastly bouncer to bin directory..."
    cp "$VENV_PATH/bin/crowdsec-fastly-bouncer" "$BIN_DIR/"

    # Copy the bouncer template configuration file if it exists
    msg info "Setting up bouncer configuration file..."
    assert_can_write_to_path "$BOUNCER_CONFIG_FULL_PATH"
    
    # Generate basic config using the bouncer's -g flag
    mkdir -p "$(dirname "$BOUNCER_CONFIG_FULL_PATH")"

    msg info "Removing existing configuration file if any..."
    rm -f "$BOUNCER_CONFIG_FULL_PATH" 2>/dev/null

    msg info "Generating bouncer configuration file..."
    msg info "with token ${FASTLY_API_TOKENS:0:5}..."
    msg info "Bouncer configuration file path: $BOUNCER_CONFIG_FULL_PATH"
    msg info "using binary $BIN_DIR/crowdsec-fastly-bouncer"    

    # tweak while we fix bouncer
    # Generate configuration file, it will fail because it created config file after, so we'll run it twice
        # for now we don't put condition as it fails for silly reasons but doesn't really
        # if "$BIN_DIR/crowdsec-fastly-bouncer" -g "$FASTLY_API_TOKENS" -o "$BOUNCER_CONFIG_FULL_PATH" -c "$BOUNCER_CONFIG_FULL_PATH" 2>/dev/null; then
    "$BIN_DIR/crowdsec-fastly-bouncer" -g "$FASTLY_API_TOKENS" -o "$BOUNCER_CONFIG_FULL_PATH" -c "$BOUNCER_CONFIG_FULL_PATH" 2>/dev/null
    # Now we should have config file
    chmod 0600 "$BOUNCER_CONFIG_FULL_PATH"
    msg succ "Configuration file created: $BOUNCER_CONFIG_FULL_PATH"
  
    # Retrieve LAPI url from CrowdSec config and save it to bouncer config
    msg info "Setting LAPI URL in bouncer configuration..."
    CROWDSEC_LAPI_URL=$(get_param_value_from_yaml "${CROWDSEC_DIR}/config.yaml" "api.server.listen_uri")
    change_param "$BOUNCER_CONFIG_FULL_PATH" 'lapi_url' "http://${CROWDSEC_LAPI_URL}"
    
    # Link bouncer to LAPI & update it's config with generated bouncer LAPI token
    msg info "Linking bouncer to LAPI and updating configuration..."
    link_bouncer_to_lapi "$BOUNCER_CONFIG_FULL_PATH" "$BOUNCER_FULL_NAME" "lapi_key"
    msg info "Bouncer linked to LAPI"
   
    # if recaptcha config variable present update config
    if [ -n "${RECAPTCHA_SECRET:-}" ] && [ -n "${RECAPTCHA_SITE_KEY:-}" ]; then
        msg info "updating recaptcha configuration..."
        change_param "$BOUNCER_CONFIG_FULL_PATH" "recaptcha_secret_key" "$RECAPTCHA_SECRET"
        change_param "$BOUNCER_CONFIG_FULL_PATH" "recaptcha_site_key" "$RECAPTCHA_SITE_KEY"
        msg succ "Recaptcha configuration updated in bouncer"
    else
        msg info "Recaptcha configuration not enabled, to enable it add variables RECAPTCHA_SECRET and RECAPTCHA_SITE_KEY"
    fi

    msg info "Updating cache and log path"
    mkdir -p "$VAR_DIR/cache"
    change_param "$BOUNCER_CONFIG_FULL_PATH" "cache_path" "$VAR_DIR/cache/fastly-cache.json"
    change_param "$BOUNCER_CONFIG_FULL_PATH" "log_file" "$LOG_DIR/$BOUNCER_FULL_NAME.log"
    msg succ "Cache and log paths updated in bouncer configuration"
}

# Test Fastly bouncer configuration
test_fastly_bouncer_config() {
    msg info "=== Testing final configuration ==="
        
    if [ -f "$BOUNCER_CONFIG_FULL_PATH" ]; then
       # check that the config file doesn't contain the default values: 
    else
        msg err "Configuration file not found: $BOUNCER_CONFIG_FULL_PATH"
        return 1
    fi
}

start_fastly_bouncer() {
    msg info "Reloading systemd user services..."
    systemctl --user daemon-reload

    msg info "Activating crowdsec-fastly-bouncer with user..."
    systemctl --user enable crowdsec-fastly-bouncer.service

    msg info "Starting crowdsec-fastly-bouncer with user..."
    if systemctl --user start crowdsec-fastly-bouncer.service; then
        msg succ "crowdsec-fastly-bouncer started with user"
    else
        msg err "Failed to start crowdsec-fastly-bouncer with user"
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