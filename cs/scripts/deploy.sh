#!/bin/bash

LOGFILE="${HOME}/deploy.log"
INSTALL_DIR="${HOME}/install"
CROWDSEC_DIR="${HOME}/crowdsec"
CROWDSEC_VERSION="v1.6.8"


if [ ! -f $LOGFILE ]; then
    echo "Deploy started at $(date)" > $LOGFILE
else
    echo "Deploy started at $(date)" >> $LOGFILE
fi

echo "Deploying CrowdSec" >> $LOGFILE
# Define the base directory

cd $INSTALL_DIR
wget "https://github.com/crowdsecurity/crowdsec/releases/download/${CROWDSEC_VERSION}/crowdsec-release.tgz"
tar -xvzf crowdsec-release.tgz
cp ./crowdsec-setup.sh "crowdsec-${CROWDSEC_VERSION}/"
cd "crowdsec-${CROWDSEC_VERSION}"
bash crowdsec-setup.sh --directory $CROWDSEC_DIR


