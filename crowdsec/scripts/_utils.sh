#!/bin/sh
#shellcheck disable=SC3043

set -eu

# This is a generic library of utility functions that can be sourced by
# bouncer installation scripts.
#
# While not requiring bash, it is not strictly POSIX-compliant because
# it uses local variables, but it should work with every modern shell.

CSCLI_CMD="${CROWDSEC_DIR}/cscli -c ${CROWDSEC_DIR}/config.yaml"

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

# Try to Create and test write access to a directory
assert_can_write_to_path() {
    if [ ! -w "$(dirname "$1")" ] 2>/dev/null; then
        mkdir -p "$(dirname "$1")" 2>/dev/null || {
            msg err "Cannot write to config directory: $(dirname "$1")"
            exit 1
        }
    fi
}

# usage get_param_value_from_yaml <path to yaml file> <path of parameter>
## example get_param_value_from_yaml /etc/crowdsec/config.yaml api.server.listen_uri
get_param_value_from_yaml() {
    local file="$1"
    local path="$2"
    
    # Split the path by dots
    IFS='.' read -ra KEYS <<< "$path"
    
    local current_output=""
    
    # Start with the entire file for the first key
    current_output=$(cat "$file")
    
    # Process each key in sequence
    for i in "${!KEYS[@]}"; do
        local key="${KEYS[$i]}"
        
        if [ $i -eq 0 ]; then
            # First key: search from beginning of file
            current_output=$(echo "$current_output" | grep -A50 "^${key}:")
        else
            # Subsequent keys: search within previous results
            current_output=$(echo "$current_output" | grep -A20 "${key}:")
        fi
        
        # If no match found, return empty
        if [ -z "$current_output" ]; then
            return 1
        fi
    done
    
    # Extract the final value (everything after the last colon and spaces)
    echo "$current_output" | head -1 | awk '{print $2}'
}

install_executable() {
    local source_path="$1"
    local dest_path="$2"
    
    # Validate required parameters
    if [[ -z "$source_path" || -z "$dest_path" ]]; then
        msg err "Usage: install_executable <source_path> <dest_path>"
        return 1
    fi
    
    # Remove existing file and install new one
    rm -f "$dest_path"
    install -v -m 0755 -D "$source_path" "$dest_path"
}

# We'll assume here the config full path ponts to the template file of the bouncer ready to be envsubst
link_bouncer_to_lapi() {
    local bouncer_name="$1"
    local bouncer_config_fullpath="$2"
    local api_key was_successful
    # if we can't set the key, the user will take care of it
    was_successful=0

    # Use the generic bouncer registration function
    if api_key=$(register_bouncer); then
        msg succ "API Key successfully created"
        # API_KEY is already exported by register_bouncer
    else
        msg err "Failed to register bouncer with CrowdSec"
        api_key="<API_KEY>"
        was_successful=1
    fi

    if [ "$api_key" != "" ] && [ "$api_key" != "<API_KEY>" ]; then
        set_config_var_value 'API_KEY' "$api_key"
    fi

    return "$ret"
}

# Register a bouncer with CrowdSec and return the API key
register_bouncer_to_lapi() {
    local bouncer_name="$1"
    local generated_api_key
    
    generated_api_key=$("${CSCLI_CMD} bouncer add ${bouncer_name}" -o raw 2>/dev/null || true)
    
    if [ -z "$generated_api_key" ]; then
        msg err "Failed to register bouncer: $bouncer_name"
        return 1
    fi
    
    msg succ "Bouncer registered successfully: $bouncer_name"
    
    echo "$generated_api_key"
}

# Delete a bouncer from CrowdSec
delete_bouncer() {
    local bouncer_name="$1"
    local cscli_cmd
    
    # If no bouncer name provided, try to get it from the stored ID
    if [ -z "$bouncer_name" ] && [ -n "${CONFIG:-}" ] && [ -f "$CONFIG.id" ]; then
        bouncer_name=$(cat "$CONFIG.id")
    fi
    
    if [ -z "$bouncer_name" ]; then
        msg err "No bouncer name provided for deletion"
        return 1
    fi
    
    # Use the specific cscli path for /app/cs environment
    cscli_cmd="${CROWDSEC_DIR:-/app/cs/etc/crowdsec}/cscli"
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