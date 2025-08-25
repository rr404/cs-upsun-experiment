#!/usr/bin/env bash

# Set variables for the bouncer installation
BOUNCER_FULL_NAME="crowdsec-cloudflare-worker-bouncer"

BOUNCER_VERSION_MIN="v0.0.14"
BOUNCER_VERSION="${BOUNCER_VERSION:-${BOUNCER_VERSION_MIN}}"
DOWNLOAD_URL="https://github.com/crowdsecurity/cs-cloudflare-worker-bouncer/releases/download/${BOUNCER_VERSION}/${BOUNCER_FULL_NAME}-linux-amd64.tgz"

BOUNCER_CONFIG="$BOUNCER_FULL_NAME.yaml"
BOUNCER_CONFIG_FULL_PATH="$CROWDSEC_DIR/bouncers/$BOUNCER_CONFIG"

BOUNCER_BIN_FULL_PATH="${BOUNCER_BIN_FULL_PATH:-${BIN_DIR:-/app/cs/usr/local/bin}/$BOUNCER_FULL_NAME}"

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

## Source utilse function functions
CROWDSEC_UTILS_SCRIPT="$(dirname "$0")/_utils.sh"
source "$CROWDSEC_UTILS_SCRIPT" || {
    echo "Error: Could not source CrowdSec utils script: $CROWDSEC_UTILS_SCRIPT"
    exit 1
}

#==========================================================================#

# Main deployment flow
main() {
    msg info "Starting Cloudflare bouncer deployment"  
    download_bouncer_release
    install_bouncer
    
    # Setup bouncer: generating worker on CF + filling config with CF zones config
    setup_cloudflare_worker
    
    # Test configuration
    if "$BOUNCER_BIN_FULL_PATH" -c "$BOUNCER_CONFIG_FULL_PATH" -t 2>&1 | grep -q "config is valid"; then
        msg succ "Cloudflare bouncer deployed successfully!"
        return 0
    else
        msg warn "Deployment completed with warnings"
        return 1
    fi
    
    # Show deployment summary
    show_deployment_summary
}

download_bouncer_release() {
    msg info "=== Downloading ${BOUNCER_FULL_NAME} ${BOUNCER_VERSION} release ==="
    
    # Create necessary directories and going to TMP_DIR
    mkdir -p "$TMP_DIR" "$(dirname "$BOUNCER_BIN_FULL_PATH")" "$(dirname "$BOUNCER_CONFIG_FULL_PATH")"
    cd "$TMP_DIR"

    # Download in TMP if not already present
    local archive_name=$(basename "$DOWNLOAD_URL")
    if [ ! -f "$archive_name" ]; then
        msg info "Downloading ${BOUNCER_FULL_NAME} ${BOUNCER_VERSION}..."
        wget "$DOWNLOAD_URL" || {
            msg err "Failed to download bouncer"
            exit 1
        }
        msg succ "Download completed"
    else
        msg info "Archive already present, reusing"
    fi

    # Extract and cd into the bouncer directory
    msg info "Extracting bouncer..."
    tar -xzf "$archive_name"
    cd "${BOUNCER_FULL_NAME}-${BOUNCER_VERSION}/"
    
    # Update BIN_PATH for the helper functions
    # BIN_PATH="./${BOUNCER}" #??delete
    
    msg succ "Release downloaded and extracted successfully"
}

# assuming we're running this from within the extracted bouncer release directory
install_bouncer() {
    msg info "=== Installing binary and initial configuration ==="
    
    # Install the bouncer binary
    msg info "Installing bouncer binary..."
    assert_can_write_to_path "$BOUNCER_BIN_FULL_PATH"
    install_executable "$TMP_DIR/${BOUNCER_FULL_NAME}-${BOUNCER_VERSION}/${BOUNCER_FULL_NAME}" "$BOUNCER_BIN_FULL_PATH"
    msg succ "Binary installed: $BOUNCER_BIN_FULL_PATH"

    # Copy the bouncer template configuration file
    msg info "Installing bouncer configuration file..."
    assert_can_write_to_path "$BOUNCER_CONFIG_FULL_PATH"
    cp "config/${BOUNCER_CONFIG}" "$BOUNCER_CONFIG_FULL_PATH"
    chmod 0600 "$BOUNCER_CONFIG_FULL_PATH"
    
    # Retrieve LAPI url from CrowdSec config and save it to bouncer config
    msg info "Setting LAPI URL in bouncer configuration..."
    CROWDSEC_LAPI_URL=$(get_param_value_from_yaml "${CROWDSEC_DIR}/config.yaml" "api.server.listen_uri")
    set_config_var_value "$BOUNCER_CONFIG_FULL_PATH" 'CROWDSEC_LAPI_URL' "http://${CROWDSEC_LAPI_URL}"
    
    # Link bouncer to LAPI & update it's config with generated bouncer LAPI token
    msg info "Linking bouncer to LAPI and updating configuration..."
    link_bouncer_to_lapi "$BOUNCER_CONFIG_FULL_PATH" "$BOUNCER_FULL_NAME" "lapi_key"
}

# Generate Cloudflare Worker configuration and deploy to Cloudflare
setup_cloudflare_worker() {
    require 'BOUNCER_CONFIG_FULL_PATH' 'BOUNCER_BIN_FULL_PATH'
    local cloudflare_tokens
    
    cloudflare_tokens="${CLOUDFLARE_API_TOKENS:-}"
    if [ -z "$cloudflare_tokens" ]; then
        msg warn "CLOUDFLARE_API_TOKENS not set - skipping Worker deployment"
        return 1
    fi
    
    msg info "Generating Cloudflare Worker configuration and deploying to Cloudflare..."
    
    # Generate config and deploy Worker to Cloudflare
    if "$BOUNCER_BIN_FULL_PATH" -c "$BOUNCER_CONFIG_FULL_PATH" -g "$cloudflare_tokens" -o "$BOUNCER_CONFIG_FULL_PATH" 2>/dev/null; then
        msg succ "Cloudflare Worker deployed and configuration generated: $BOUNCER_CONFIG_FULL_PATH"
        return 0
    else
        msg err "Failed to generate Cloudflare Worker configuration and deploy"
        return 1
    fi
}

show_deployment_summary() {
    msg info "=== Deployment Summary ==="
    msg info "Configuration file: $BOUNCER_CONFIG_FULL_PATH"
    msg info "Binary: $BOUNCER_BIN_FULL_PATH"
    msg info "Version: $BOUNCER_VERSION"
    
    if [ -n "${CLOUDFLARE_API_TOKENS:-}" ]; then
        msg info "Cloudflare tokens: Configured"
    else
        msg warn "Cloudflare tokens: Not configured"
    fi
}

#==========================================================================#

# Execute main deployment
main "$@"
