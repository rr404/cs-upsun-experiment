#!/usr/bin/env bash

echo "Deploying Cloudflare Bouncer"
CF_BOUNCER_VERSION="v0.0.14"

cd $TMP_DIR

wget "https://github.com/crowdsecurity/cs-cloudflare-worker-bouncer/releases/download/${CF_BOUNCER_VERSION}/crowdsec-cloudflare-worker-bouncer-linux-amd64.tgz"
