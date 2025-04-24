#!/bin/bash

CROWDSEC_ROOT_DIR="${HOME}/crowdsec-root"
LOGFILE="${CROWDSEC_ROOT_DIR}/deploy.log"

if [ ! -f $LOGFILE ]; then
    echo "Deploy started at $(date)" > $LOGFILE
else
    echo "Deploy started at $(date)" >> $LOGFILE
fi
echo "Deploying CrowdSec" >> $LOGFILE

# Define the base directory

cd $CROWDSEC_ROOT_DIR
wget https://github.com/crowdsecurity/crowdsec/releases/download/v1.6.8/crowdsec-release.tgz
tar -xvzf crowdsec-release.tgz
mv crowdsec-v1.6.8 crowdsec