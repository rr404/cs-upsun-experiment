#!/bin/bash

if [ ! -f $DEPLOY_LOG_FILE ]; then
    echo "Deploy started at $(date)" > $DEPLOY_LOG_FILE
else
    echo "Deploy started at $(date)" >> $DEPLOY_LOG_FILE
fi

echo "Deploying CrowdSec" >> $DEPLOY_LOG_FILE
# Define the base directory

# cd $INSTALL_DIR
# wget "https://github.com/crowdsecurity/crowdsec/releases/download/${CROWDSEC_VERSION}/crowdsec-release.tgz"
# tar -xvzf crowdsec-release.tgz
# cp ${HOME}/scripts/crowdsec-setup.sh "crowdsec-${CROWDSEC_VERSION}/"
# cd "crowdsec-${CROWDSEC_VERSION}"
# bash crowdsec-setup.sh /app $CROWDSEC_DIR

