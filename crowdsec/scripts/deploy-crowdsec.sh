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

cd $TMP_DIR
wget "https://github.com/crowdsecurity/crowdsec/releases/download/${CROWDSEC_VERSION}/crowdsec-release.tgz"
tar -xvzf crowdsec-release.tgz
cp ${SCRIPTS_DIR}/crowdsec-setup.sh "crowdsec-${CROWDSEC_VERSION}/"
cd "crowdsec-${CROWDSEC_VERSION}"
bash crowdsec-setup.sh $CROWDSEC_DIR
cp ${SCRIPTS_DIR}/crowdsec/* -R $CROWDSEC_DIR
cd ${SCRIPTS_DIR}
bash start-crowdsec-service.sh >> $DEPLOY_LOG_FILE 2>&1
