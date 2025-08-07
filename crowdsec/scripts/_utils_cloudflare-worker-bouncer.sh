#!/bin/sh
#shellcheck disable=SC3043

set -eu

# Source generic utilities
# shellcheck source=./_utils.sh
. "$(dirname "$0")/_utils.sh"

BOUNCER="crowdsec-cloudflare-worker-bouncer"
BOUNCER_PREFIX=$(echo "$BOUNCER" | sed 's/crowdsec-/cs-/g')

# This is a library of Cloudflare Worker bouncer-specific functions that can be
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
# Use /app/cs paths for non-sudo environment
BIN_PATH_INSTALLED="${BIN_PATH_INSTALLED:-${BIN_DIR:-/app/cs/bin}/$BOUNCER}"
BIN_PATH="./$BOUNCER"
CONFIG_DIR="${CONFIG_DIR:-${CROWDSEC_DIR:-/app/cs/etc/crowdsec}/bouncers}"
CONFIG_FILE="$BOUNCER.yaml"
CONFIG="$CONFIG_DIR/$CONFIG_FILE"
# Use user systemd path instead of system
SYSTEMD_PATH_FILE="${SYSTEMD_PATH_FILE:-$HOME/.config/systemd/user/$SERVICE}"
}


# Check if the configuration file contains a variable
# which has not yet been interpolated, like "$API_KEY",
# and return true if it does.
config_not_set() {
    require 'CONFIG'
    local varname before after

    varname=$1
    if [ "$varname" = "" ]; then
        msg err "missing required variable name"
        exit 1
    fi

    before=$("$BIN_PATH_INSTALLED" -c "$CONFIG" -T 2>/dev/null || echo "")
    if [ "$before" = "" ]; then
        # If binary doesn't exist or config test fails, assume not set
        return 0
    fi
    
    # shellcheck disable=SC2016
    after=$(echo "$before" | envsubst "\$$varname" 2>/dev/null || echo "$before")

    if [ "$before" = "$after" ]; then
        return 1
    fi
    return 0
}

need_api_key() {
    if config_not_set 'API_KEY'; then
        return 0
    fi
    return 1
}

# Interpolate a variable in the config file with a value.
set_config_var_value() {
    require 'CONFIG'
    local varname value before

    varname=$1
    if [ "$varname" = "" ]; then
        msg err "missing required variable name"
        exit 1
    fi

    value=$2
    if [ "$value" = "" ]; then
        msg err "missing required variable value"
        exit 1
    fi

    before=$(cat "$CONFIG")
    echo "$before" | \
        env "$varname=$value" envsubst "\$$varname" | \
        install -m 0600 /dev/stdin "$CONFIG"
}

set_api_key() {
    require 'CONFIG'
    local api_key ret
    # if we can't set the key, the user will take care of it
    ret=0

    # Use the generic bouncer registration function
    if api_key=$(register_bouncer); then
        msg succ "API Key successfully created"
        # API_KEY is already exported by register_bouncer
    else
        msg err "Failed to register bouncer with CrowdSec"
        api_key="<API_KEY>"
        ret=1
    fi

    if [ "$api_key" != "" ] && [ "$api_key" != "<API_KEY>" ]; then
        set_config_var_value 'API_KEY' "$api_key"
    fi

    return "$ret"
}

set_local_port() {
    require 'CONFIG'
    local port cscli_cmd
    
    cscli_cmd="${CROWDSEC_DIR:-/app/cs/etc/crowdsec}/cscli"
    if [ ! -x "$cscli_cmd" ]; then
        cscli_cmd="cscli"
    fi
    
    command -v "$cscli_cmd" >/dev/null || return 0
    
    # the following will fail with a non-LAPI local crowdsec, leaving empty port
    if [ -n "${CROWDSEC_DIR:-}" ] && [ -f "${CROWDSEC_DIR}/config.yaml" ]; then
        port=$("$cscli_cmd" --config "${CROWDSEC_DIR}/config.yaml" config show -oraw --key "Config.API.Server.ListenURI" 2>/dev/null | cut -d ":" -f2 || true)
    else
        port=$("$cscli_cmd" config show -oraw --key "Config.API.Server.ListenURI" 2>/dev/null | cut -d ":" -f2 || true)
    fi
    
    if [ "$port" != "" ]; then
        sed -i "s/localhost:8080/127.0.0.1:$port/g" "$CONFIG"
        sed -i "s/127.0.0.1:8080/127.0.0.1:$port/g" "$CONFIG"
    fi
}

set_local_lapi_url() {
    require 'CONFIG'
    local port varname cscli_cmd
    # $varname is the name of the variable to interpolate
    # in the config file with the URL of the LAPI server,
    # assuming it is running on the same host as the
    # bouncer.
    varname=$1
    if [ "$varname" = "" ]; then
        msg err "missing required variable name"
        exit 1
    fi
    
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

    set_config_var_value "$varname" "http://127.0.0.1:$port"
}

# Delete Cloudflare bouncer - use generic function
# This function is now provided by the generic _utils.sh

upgrade_bin() {
    require 'BIN_PATH' 'BIN_PATH_INSTALLED'
    rm -f "$BIN_PATH_INSTALLED"
    install -v -m 0755 -D "$BIN_PATH" "$BIN_PATH_INSTALLED"
}

# Generate Cloudflare Worker configuration and deploy to Cloudflare
generate_cloudflare_worker() {
    require 'CONFIG' 'BIN_PATH_INSTALLED'
    local cloudflare_tokens
    
    cloudflare_tokens="${CLOUDFLARE_API_TOKENS:-}"
    if [ -z "$cloudflare_tokens" ]; then
        msg warn "CLOUDFLARE_API_TOKENS not set - skipping Worker deployment"
        return 1
    fi
    
    msg info "Generating Cloudflare Worker configuration and deploying to Cloudflare..."
    
    # Remove existing config to force regeneration
    rm -f "$CONFIG"
    
    # Generate config and deploy Worker to Cloudflare
    if "$BIN_PATH_INSTALLED" -g "$cloudflare_tokens" -o "$CONFIG" 2>/dev/null; then
        chmod 0600 "$CONFIG"
        msg succ "Cloudflare Worker deployed and configuration generated: $CONFIG"
        return 0
    else
        msg err "Failed to generate Cloudflare Worker configuration and deploy"
        return 1
    fi
}