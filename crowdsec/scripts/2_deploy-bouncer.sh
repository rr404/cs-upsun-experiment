#!/usr/bin/env bash

# Check if BOUNCER_TYPE is set and not empty
if [[ -n "$BOUNCER_TYPE" ]]; then
    DEPLOY_SCRIPT="2i_deploy-${BOUNCER_TYPE}-bouncer.sh"
    if [[ -f "$DEPLOY_SCRIPT" ]]; then
        echo "Chosen bouncer: ${BOUNCER_TYPE}"
        bash "$DEPLOY_SCRIPT" >> $DEPLOY_LOG_FILE 2>&1
    else
        echo "No deploy script found for bouncer type: $BOUNCER_TYPE"
    fi
else
    echo "No bouncer chosen, skipping bouncer installation."
fi