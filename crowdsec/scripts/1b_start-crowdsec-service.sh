#!/usr/bin/env bash

echo "Reload Services"
systemctl --user daemon-reload

echo "Activating crowdsec with user"
systemctl --user enable crowdsec.service

echo "Starting crowdsec with user"
systemctl --user start crowdsec.service

echo "Show current services"
systemctl --user status crowdsec.service

echo "checking CAPI user"
echo $(head -n2 ${CROWDSEC_DIR}/online_api_credentials.yaml | tail -n1)
