#!/usr/bin/env bash

echo "Deploying Cloudflare Bouncer"

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
BOUNCER_HELPER="$(dirname "$0")/_utils_cloudflare-worker-bouncer.sh"

if [ ! -f "$BOUNCER_HELPER" ]; then
    echo "Error: Bouncer helper script not found at $BOUNCER_HELPER" >&2
    exit 1
fi

source "$BOUNCER_HELPER"

## Set variables for the bouncer installation
CF_BOUNCER_VERSION_MIN="v0.0.14"
CF_BOUNCER_VERSION="${CF_BOUNCER_VERSION:-${CF_BOUNCER_VERSION_MIN}}"
DOWNLOAD_URL="https://github.com/crowdsecurity/cs-cloudflare-worker-bouncer/releases/download/${CF_BOUNCER_VERSION}/${BOUNCER}-linux-amd64.tgz"

# Cloudflare Worker-Bouncer specific functions
## Function: Download and extract the bouncer release
download_bouncer_release() {
    msg info "=== Downloading ${BOUNCER} ${CF_BOUNCER_VERSION} release ==="
    
    # Create necessary directories - ensure /app/cs paths
    mkdir -p "$CONFIG_DIR" "$TMP_DIR" "$(dirname "$BOUNCER_BIN_FULL_PATH")"
    cd "$TMP_DIR"

    # Download if not already present
    if [ ! -f "${BOUNCER}-linux-amd64.tgz" ]; then
        msg info "Downloading ${BOUNCER} ${CF_BOUNCER_VERSION}..."
        wget "$DOWNLOAD_URL" || {
            msg err "Failed to download bouncer"
            exit 1
        }
        msg succ "Download completed"
    else
        msg info "Archive already present, reusing"
    fi

    # Extract
    msg info "Extracting bouncer..."
    tar -xzf "${BOUNCER}-linux-amd64.tgz"
    cd "${BOUNCER}-${CF_BOUNCER_VERSION}/"
    
    # Update BIN_PATH for the helper functions
    BIN_PATH="./${BOUNCER}"
    
    msg succ "Release downloaded and extracted successfully"
}

## Function: Install binary and setup initial config
install_bouncer_binary() {
    msg info "=== Installing binary and initial configuration ==="
    
    # Validate we have write access before proceeding
    assert_can_write_to_path $BOUNCER_BIN_FULL_PATH
    
    # Install the binary
    msg info "Installing bouncer binary..."
    upgrade_bin
    msg succ "Binary installed: $BOUNCER_BIN_FULL_PATH"

    # Copy and setup config file if it doesn't exist
    if [ ! -f "$CONFIG" ]; then
        msg info "Setting up configuration file..."
        cp "config/${CONFIG_FILE}" "$CONFIG"
        chmod 0600 "$CONFIG"
        msg succ "Configuration file created: $CONFIG"
    else
        msg info "Configuration file exists: $CONFIG"
    fi
}

## Function: Create API key with CrowdSec
create_api_key() {
    msg info "=== Creating CrowdSec API key ==="
    
    if set_api_key; then
        msg succ "CrowdSec API key configured successfully"
        return 0
    else
        msg warn "Failed to configure API key - manual configuration required"
        return 1
    fi
}

## Function: Update config with Cloudflare tokens and LAPI settings
update_bouncer_config() {
    msg info "=== Updating configuration with tokens and parameters ==="
    
    # Set Cloudflare API tokens if provided
    if [ -n "${CLOUDFLARE_API_TOKENS:-}" ]; then
        msg info "Configuring Cloudflare tokens..."
        
        # Check what variable name the actual config file expects for v1
        if grep -q "cloudflare_token:" "$CONFIG" 2>/dev/null; then
            set_config_var_value 'CLOUDFLARE_TOKEN' "$CLOUDFLARE_API_TOKENS"
        elif grep -q "api_token:" "$CONFIG" 2>/dev/null; then
            set_config_var_value 'API_TOKEN' "$CLOUDFLARE_API_TOKENS"
        elif grep -q "token:" "$CONFIG" 2>/dev/null; then
            set_config_var_value 'TOKEN' "$CLOUDFLARE_API_TOKENS"
        else
            # Fallback: try to add it manually to the config
            msg warn "Cloudflare token field not found in config, adding manually"
            echo "api_token: $CLOUDFLARE_API_TOKENS" >> "$CONFIG"
        fi
        msg succ "Cloudflare tokens configured"
    else
        msg warn "CLOUDFLARE_API_TOKENS not defined. Manual configuration required in $CONFIG"
    fi

    # Set the local LAPI URL
    msg info "Configuring local LAPI URL..."
    if grep -q "lapi_url:" "$CONFIG" 2>/dev/null; then
        set_local_lapi_url 'LAPI_URL'
        msg succ "LAPI URL configured"
    elif grep -q "url:" "$CONFIG" 2>/dev/null; then
        set_local_lapi_url 'URL'
        msg succ "LAPI URL configured"
    else
        msg warn "LAPI URL field not found in config"
    fi

    # Update any port configurations
    msg info "Updating port configurations..."
    set_local_port
    msg succ "Configuration updated successfully"
}

## Function: Test the final configuration
test_bouncer_config() {
    msg info "=== Testing final configuration ==="
    
    if [ -x "$BOUNCER_BIN_FULL_PATH" ]; then
        msg info "Testing configuration..."
        if "$BOUNCER_BIN_FULL_PATH" -c "$CONFIG" -T >/dev/null 2>&1; then
            msg succ "Configuration test successful"
            return 0
        else
            msg warn "Configuration test failed - check $CONFIG manually"
            msg info "You can test manually with: $BOUNCER_BIN_FULL_PATH -c $CONFIG -T"
            return 1
        fi
    else
        msg warn "Binary not executable, cannot test configuration"
        return 1
    fi
}

## Function: Display deployment summary
show_deployment_summary() {
    msg info "=== Deployment Summary ==="
    msg info "Configuration file: $CONFIG"
    msg info "Binary: $BOUNCER_BIN_FULL_PATH"
    msg info "Version: $CF_BOUNCER_VERSION"
    
    if [ -n "${CLOUDFLARE_API_TOKENS:-}" ]; then
        msg info "Cloudflare tokens: Configured"
    else
        msg warn "Cloudflare tokens: Not configured"
    fi
}

# Main deployment flow
main() {
    msg info "Starting Cloudflare bouncer deployment"
    
    # Step 1: Download bouncer release
    download_bouncer_release
    
    # Step 2: Install binary and setup initial config
    install_bouncer_binary
    
    # Step 3: Generate Cloudflare Worker and deploy to Cloudflare
    if generate_cloudflare_worker; then
        msg succ "Cloudflare Worker deployment completed"
    else
        msg warn "Cloudflare Worker deployment failed - continuing with manual configuration"
    fi
    
    # Step 4: Create API key
    if ! create_api_key; then
        msg warn "Continuing despite API key creation failure..."
    fi
    
    # Step 5: Update config with tokens and settings
    update_bouncer_config
    
    # Step 6: Test configuration
    if test_bouncer_config; then
        msg succ "Cloudflare bouncer deployed successfully!"
    else
        msg warn "Deployment completed with warnings"
    fi
    
    # Step 7: Show summary
    show_deployment_summary
}

# Execute main deployment
main "$@"