#!/usr/bin/env bash

# Deploy bouncer(s) based on available API tokens
echo "Checking bouncer deployment configuration..." >> $DEPLOY_LOG_FILE

# Track if any bouncers were deployed
DEPLOYED_BOUNCERS=()

# Function to deploy a specific bouncer type
deploy_bouncer() {
    local bouncer_type="$1"
    local deploy_script="2i_deploy-${bouncer_type}-bouncer.sh"
    
    # Check if the specific bouncer deployment script exists
    if [[ -f "${SCRIPTS_DIR}/${deploy_script}" ]]; then
        echo "Deploying ${bouncer_type} bouncer..." >> $DEPLOY_LOG_FILE
        cd "${SCRIPTS_DIR}"
        bash "$deploy_script" >> $DEPLOY_LOG_FILE 2>&1
        
        # Check if deployment was successful
        if [[ $? -eq 0 ]]; then
            echo "Successfully deployed ${bouncer_type} bouncer" >> $DEPLOY_LOG_FILE
            DEPLOYED_BOUNCERS+=("$bouncer_type")
            return 0
        else
            echo "Warning: ${bouncer_type} bouncer deployment completed with errors" >> $DEPLOY_LOG_FILE
            return 1
        fi
    else
        echo "Error: No deploy script found for bouncer type: ${bouncer_type}" >> $DEPLOY_LOG_FILE
        echo "Expected script: ${SCRIPTS_DIR}/${deploy_script}" >> $DEPLOY_LOG_FILE
        return 1
    fi
}

# Check for Cloudflare API tokens and deploy if available
if [[ -n "${CLOUDFLARE_API_TOKENS:-}" ]]; then
    echo "Cloudflare API tokens detected - deploying Cloudflare bouncer" >> $DEPLOY_LOG_FILE
    deploy_bouncer "cloudflare"
fi

# Check for Fastly API tokens and deploy if available
if [[ -n "${FASTLY_API_TOKENS:-}" ]]; then
    echo "Fastly API tokens detected - deploying Fastly bouncer" >> $DEPLOY_LOG_FILE
    deploy_bouncer "fastly"
fi

# Summary
if [[ ${#DEPLOYED_BOUNCERS[@]} -gt 0 ]]; then
    echo "Bouncer deployment completed. Deployed bouncers: ${DEPLOYED_BOUNCERS[*]}" >> $DEPLOY_LOG_FILE
else
    echo "No bouncers deployed - no API tokens found" >> $DEPLOY_LOG_FILE
    echo "To deploy bouncers, set the appropriate API token variables:" >> $DEPLOY_LOG_FILE
    echo "  - CLOUDFLARE_API_TOKENS for Cloudflare bouncer" >> $DEPLOY_LOG_FILE
    echo "  - FASTLY_API_TOKENS for Fastly bouncer" >> $DEPLOY_LOG_FILE
    echo "  - Or use legacy BOUNCER_TYPE variable" >> $DEPLOY_LOG_FILE
fi