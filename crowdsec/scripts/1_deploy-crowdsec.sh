#!/usr/bin/env bash

if [ ! -f $DEPLOY_LOG_FILE ]; then
    echo "Deploy started at $(date)" > $DEPLOY_LOG_FILE
else
    echo "Deploy started at $(date)" >> $DEPLOY_LOG_FILE
fi

echo "Deploying CrowdSec" >> $DEPLOY_LOG_FILE
# Define the base directory

mkdir -p $LOG_DIR
mkdir -p $TMP_DIR
mkdir -p $CROWDSEC_DIR

# Download and setup CrowdSec
cd $TMP_DIR
wget "https://github.com/crowdsecurity/crowdsec/releases/download/${CROWDSEC_VERSION}/crowdsec-release.tgz"
tar -xvzf crowdsec-release.tgz
cp ${SCRIPTS_DIR}/crowdsec-setup.sh "crowdsec-${CROWDSEC_VERSION}/"
cd "crowdsec-${CROWDSEC_VERSION}"
bash 1a_crowdsec-setup.sh $CROWDSEC_DIR

# Copy binaries dependencies
mkdir -p $BIN_DIR
cp ${SCRIPTS_DIR}/bin/* $BIN_DIR

# Start CrowdSec service
cp ${SCRIPTS_DIR}/crowdsec/* -R $CROWDSEC_DIR
cd ${SCRIPTS_DIR}
bash 1b_start-crowdsec-service.sh >> $DEPLOY_LOG_FILE 2>&1
