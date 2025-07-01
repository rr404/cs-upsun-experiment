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
## deleting old crowdsec directories
rm crowdsec* -R

## CrowdSec Security Engine Install
### Checking if we need to re-install CrowdSec
LOCKFILE="${$TMP_DIR}/LAST_INSTALLED_${CROWDSEC_VERSION}${REINSTALL_SUFFIX}.lock"
if [[ ! -f "$LOCKFILE" ]]; then
    # If the specific lock file does NOT exist, delete all LAST_INSTALLED_*.lock files
    rm -f LAST_INSTALLED_*.lock

    ### Retrieving CrowdSec release
    wget "https://github.com/crowdsecurity/crowdsec/releases/download/${CROWDSEC_VERSION}/crowdsec-release.tgz"
    
        #### Alternative uncomment to compile (requieres those in composable stack : "go", "rsyslog", "netcat", "gnumake", "tcpdump")
        # git clone https://github.com/crowdsecurity/crowdsec.git -b http-datasource-get-head
        # cd crowdsec
        # GOMODCACHE=/app/cs/tmp/pkg/mod GOPATH=/app/cs/tmp/go GOCACHE=/app/cs/tmp/go-build make release BUILD_RE2_WASM=1
        # cd ..
    
    ## Extracting CrowdSec release
    cp crowdsec/crowdsec-release.tgz .
    tar -xvzf crowdsec-release.tgz
    ## deleting release archives
    rm crowdsec-release.tgz

    ### CrowdSec setup
    cp ${SCRIPTS_DIR}/1a_crowdsec-setup.sh crowdsec-*/
    #cp ${SCRIPTS_DIR}/1a_crowdsec-setup.sh "crowdsec-${CROWDSEC_VERSION}/"
    # cd "crowdsec-${CROWDSEC_VERSION}" #old version, the wild card should work as we delete all other crowdsec* dir earlier
    cd crowdsec-*
    bash 1a_crowdsec-setup.sh $CROWDSEC_DIR

    ### Start CrowdSec service
    cp ${SCRIPTS_DIR}/crowdsec/* -R $CROWDSEC_DIR
    cd ${SCRIPTS_DIR}
    bash 1b_start-crowdsec-service.sh >> $DEPLOY_LOG_FILE 2>&1

    ###
    if systemctl --user is-active --quiet crowdsec; then
        # Create the lock file to indicate successful install
        touch "$LOCKFILE"
    fi
else
    echo "CrowdSec is already installed with version ${CROWDSEC_VERSION}${REINSTALL_SUFFIX}. Skipping installation." >> $DEPLOY_LOG_FILE
fi


