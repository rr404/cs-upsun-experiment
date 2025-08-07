#!/usr/bin/env bash

echo "Deploying Fastly Bouncer"

# Pre-requisites sourcing and variables setup
## Source the environment variables first
if [ -f "${PLATFORM_APP_DIR}/.environment" ]; then
    source "${PLATFORM_APP_DIR}/.environment"
fi

## Ensure TMP_DIR is available for the script
if [ -z "${TMP_DIR:-}" ]; then
    TMP_DIR="/tmp"
fi

## Source the bouncer helper functions
BOUNCER_HELPER="$(dirname "$0")/_utils_fastly-bouncer.sh"

if [ ! -f "$BOUNCER_HELPER" ]; then
    echo "Error: Bouncer helper script not found at $BOUNCER_HELPER" >&2
    exit 1
fi

source "$BOUNCER_HELPER"

# Fastly Bouncer specific functions
## Function: Setup Python environment and install bouncer
setup_python_environment() {
    msg info "=== Setting up Python environment ==="
    
    # Check Python requirements
    if ! check_python_requirements; then
        msg err "Python requirements not met"
        exit 1
    fi
    
    # Setup virtual environment
    if ! setup_python_venv; then
        msg err "Failed to setup Python virtual environment"
        exit 1
    fi
    
    msg succ "Python environment setup completed"
}

## Function: Install Fastly bouncer
install_fastly_bouncer_package() {
    msg info "=== Installing Fastly bouncer package ==="
    
    # Validate we have write access before proceeding
    assert_can_write_to_path "$VENV_PATH/bin/crowdsec-fastly-bouncer"
    
    # Install the bouncer via pip
    if ! install_fastly_bouncer; then
        msg err "Failed to install Fastly bouncer"
        exit 1
    fi
    
    msg succ "Fastly bouncer package installed successfully"
}

## Function: Generate and setup configuration
setup_fastly_configuration() {
    msg info "=== Setting up Fastly bouncer configuration ==="
    
    # Generate configuration file
    if ! generate_fastly_config; then
        msg err "Failed to generate Fastly configuration"
        exit 1
    fi
    
    msg succ "Configuration file generated: $CONFIG"
}

## Function: Create API key with CrowdSec
create_api_key() {
    msg info "=== Creating CrowdSec API key ==="
    
    if set_fastly_api_key; then
        msg succ "CrowdSec API key configured successfully"
        return 0
    else
        msg warn "Failed to configure API key - manual configuration required"
        return 1
    fi
}

## Function: Update config with LAPI settings
update_bouncer_config() {
    msg info "=== Updating configuration with LAPI settings ==="
    
    # Set the local LAPI URL
    msg info "Configuring local LAPI URL..."
    set_fastly_lapi_url
    msg succ "LAPI URL configured"
    
    # Display Fastly token status
    if [ -n "${FASTLY_API_TOKEN:-}" ]; then
        msg info "Fastly API tokens: Configured"
    else
        msg warn "FASTLY_API_TOKEN not defined. Manual configuration required in $CONFIG"
        msg info "You need to set the Fastly API tokens in the configuration file"
    fi
    
    msg succ "Configuration updated successfully"
}

## Function: Test the final configuration
test_bouncer_config() {
    msg info "=== Testing final configuration ==="
    
    if test_fastly_config; then
        msg succ "Configuration test successful"
        return 0
    else
        msg warn "Configuration test failed - check $CONFIG manually"
        msg info "You can test manually with: crowdsec-fastly-bouncer -c $CONFIG -t"
        return 1
    fi
}

## Function: Display deployment summary
show_deployment_summary() {
    msg info "=== Deployment Summary ==="
    msg info "Configuration file: $CONFIG"
    msg info "Virtual environment: $VENV_PATH"
    msg info "Bouncer: crowdsec-fastly-bouncer (installed via pip)"
    
    if [ -n "${FASTLY_API_TOKEN:-}" ]; then
        msg info "Fastly API tokens: Configured"
    else
        msg warn "Fastly API tokens: Not configured"
    fi
    
    msg info "To run the bouncer manually:"
    msg info "  source $VENV_PATH/bin/activate"
    msg info "  crowdsec-fastly-bouncer -c $CONFIG"
}

# Main deployment flow
main() {
    msg info "Starting Fastly bouncer deployment"
    
    # Step 1: Setup Python environment
    setup_python_environment
    
    # Step 2: Install Fastly bouncer package
    install_fastly_bouncer_package
    
    # Step 3: Generate initial configuration
    setup_fastly_configuration
    
    # Step 4: Create API key
    if ! create_api_key; then
        msg warn "Continuing despite API key creation failure..."
    fi
    
    # Step 5: Update config with LAPI settings
    update_bouncer_config
    
    # Step 6: Test configuration
    if test_bouncer_config; then
        msg succ "Fastly bouncer deployed successfully!"
    else
        msg warn "Deployment completed with warnings"
    fi
    
    # Step 7: Show summary
    show_deployment_summary
}

# Execute main deployment
main "$@"