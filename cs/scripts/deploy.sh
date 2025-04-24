#!/bin/bash
# Define the base directory
BASE_DIR=~/.global/nix-env/root
LOG_DIR="${BASE_DIR}/share/log"

### Checking if crowdsec is installed
# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Create deploy log file
DEPLOY_LOG="${LOG_DIR}/deploy.log"
touch "$DEPLOY_LOG"

# Log deployment start
echo "$(date): Deploying..." >> "$DEPLOY_LOG"

# Check if crowdsec log directory exists
CROWDSEC_LOG_DIR="${LOG_DIR}/crowdsec"
if [ -d "$CROWDSEC_LOG_DIR" ]; then
    echo "$(date): CrowdSec log directory exists at $CROWDSEC_LOG_DIR" >> "$DEPLOY_LOG"
else
    echo "$(date): CrowdSec log directory does NOT exist at $CROWDSEC_LOG_DIR" >> "$DEPLOY_LOG"
fi

# Check if crowdsec config.yaml exists
# Note: There seems to be a typo in your path (config/config/yaml), I'm assuming you meant config/config.yaml
CROWDSEC_CONFIG="${CROWDSEC_LOG_DIR}/config/config.yaml"
if [ -f "$CROWDSEC_CONFIG" ]; then
    echo "$(date): CrowdSec config.yaml exists at $CROWDSEC_CONFIG" >> "$DEPLOY_LOG"
else
    echo "$(date): CrowdSec config.yaml does NOT exist at $CROWDSEC_CONFIG" >> "$DEPLOY_LOG"
fi

# Check if there's a potential alternative path for the config file
ALT_CONFIG_DIR="${BASE_DIR}/share/crowdsec/config"
if [ -d "$ALT_CONFIG_DIR" ]; then
    ALT_CONFIG="${ALT_CONFIG_DIR}/config.yaml"
    if [ -f "$ALT_CONFIG" ]; then
        echo "$(date): Found alternative CrowdSec config.yaml at $ALT_CONFIG" >> "$DEPLOY_LOG"
    fi
fi

echo "$(date): Deployment log check completed" >> "$DEPLOY_LOG"
echo "Log file created at: $DEPLOY_LOG"