#!/bin/sh
#shellcheck disable=SC3043

set -eu

# This is a generic library of utility functions that can be sourced by
# bouncer installation scripts.
#
# While not requiring bash, it is not strictly POSIX-compliant because
# it uses local variables, but it should work with every modern shell.

# Color management for terminal output
if [ ! -t 0 ]; then
    # terminal is not interactive; no colors
    FG_RED=""
    FG_GREEN=""
    FG_YELLOW=""
    FG_CYAN=""
    RESET=""
elif tput sgr0 >/dev/null 2>&1; then
    # terminfo
    FG_RED=$(tput setaf 1)
    FG_GREEN=$(tput setaf 2)
    FG_YELLOW=$(tput setaf 3)
    FG_CYAN=$(tput setaf 6)
    RESET=$(tput sgr0)
else
    FG_RED=$(printf '%b' '\033[31m')
    FG_GREEN=$(printf '%b' '\033[32m')
    FG_YELLOW=$(printf '%b' '\033[33m')
    FG_CYAN=$(printf '%b' '\033[36m')
    RESET=$(printf '%b' '\033[0m')
fi

# Generic message function with color support
msg() {
    case "$1" in
        info) echo "${FG_CYAN}$2${RESET}" >&2 ;;
        warn) echo "${FG_YELLOW}WARN:${RESET} $2" >&2 ;;
        err) echo "${FG_RED}ERR:${RESET} $2" >&2 ;;
        succ) echo "${FG_GREEN}$2${RESET}" >&2 ;;
        *) echo "$1" >&2 ;;
    esac
}

# Require environment variables to be set
require() {
    set | grep -q "^$1=" || { msg err "missing required variable \$$1"; exit 1; }
    shift
    [ "$#" -eq 0 ] || require "$@"
}

# Assert write permissions for non-sudo environment
assert_root() {
    # In non-sudo /app/cs environment, just validate we have write access
    if [ ! -w "$(dirname "$BIN_PATH_INSTALLED")" ] 2>/dev/null; then
        mkdir -p "$(dirname "$BIN_PATH_INSTALLED")" 2>/dev/null || {
            msg err "Cannot write to binary directory: $(dirname "$BIN_PATH_INSTALLED")"
            exit 1
        }
    fi
    if [ ! -w "$(dirname "$CONFIG")" ] 2>/dev/null; then
        mkdir -p "$(dirname "$CONFIG")" 2>/dev/null || {
            msg err "Cannot write to config directory: $(dirname "$CONFIG")"
            exit 1
        }
    fi
}

# Register a bouncer with CrowdSec and return the API key
register_bouncer() {
    require 'BOUNCER_PREFIX'
    local bouncer_name api_key cscli_cmd
    
    bouncer_name="${1:-$BOUNCER_PREFIX-$(date +%s)}"
    
    # Use the specific cscli path for /app/cs environment
    cscli_cmd="${CROWDSEC_DIR:-/app/cs}/cscli"
    if [ ! -x "$cscli_cmd" ]; then
        cscli_cmd="cscli"
    fi

    if ! command -v "$cscli_cmd" >/dev/null; then
        msg err "cscli not found"
        return 1
    fi

    msg info "Registering bouncer: $bouncer_name"
    
    # Use config file if available
    if [ -n "${CROWDSEC_DIR:-}" ] && [ -f "${CROWDSEC_DIR}/config.yaml" ]; then
        api_key=$("$cscli_cmd" --config "${CROWDSEC_DIR}/config.yaml" bouncer add "$bouncer_name" -o raw 2>/dev/null || true)
    else
        api_key=$("$cscli_cmd" bouncer add "$bouncer_name" -o raw 2>/dev/null || true)
    fi
    
    if [ -z "$api_key" ]; then
        msg err "Failed to register bouncer: $bouncer_name"
        return 1
    fi
    
    msg succ "Bouncer registered successfully: $bouncer_name"
    
    # Store bouncer name for potential deletion
    if [ -n "${CONFIG:-}" ]; then
        echo "$bouncer_name" > "$CONFIG.id"
    fi
    
    # Export API_KEY for use by calling functions
    API_KEY="$api_key"
    export API_KEY
    
    echo "$api_key"
}

# Delete a bouncer from CrowdSec
delete_bouncer() {
    local bouncer_name cscli_cmd
    
    bouncer_name="${1:-}"
    
    # If no bouncer name provided, try to get it from the stored ID
    if [ -z "$bouncer_name" ] && [ -n "${CONFIG:-}" ] && [ -f "$CONFIG.id" ]; then
        bouncer_name=$(cat "$CONFIG.id")
    fi
    
    if [ -z "$bouncer_name" ]; then
        msg err "No bouncer name provided for deletion"
        return 1
    fi
    
    # Use the specific cscli path for /app/cs environment
    cscli_cmd="${CROWDSEC_DIR:-/app/cs}/cscli"
    if [ ! -x "$cscli_cmd" ]; then
        cscli_cmd="cscli"
    fi

    if ! command -v "$cscli_cmd" >/dev/null; then
        msg err "cscli not found"
        return 1
    fi

    msg info "Deleting bouncer: $bouncer_name"
    
    # Use config file if available
    if [ -n "${CROWDSEC_DIR:-}" ] && [ -f "${CROWDSEC_DIR}/config.yaml" ]; then
        if "$cscli_cmd" --config "${CROWDSEC_DIR}/config.yaml" bouncers delete "$bouncer_name" >/dev/null 2>&1; then
            msg succ "Bouncer deleted successfully: $bouncer_name"
        else
            msg warn "Failed to delete bouncer: $bouncer_name (may not exist)"
        fi
    else
        if "$cscli_cmd" bouncers delete "$bouncer_name" >/dev/null 2>&1; then
            msg succ "Bouncer deleted successfully: $bouncer_name"
        else
            msg warn "Failed to delete bouncer: $bouncer_name (may not exist)"
        fi
    fi
    
    # Clean up stored ID
    if [ -n "${CONFIG:-}" ] && [ -f "$CONFIG.id" ]; then
        rm -f "$CONFIG.id"
    fi
    
    return 0
}