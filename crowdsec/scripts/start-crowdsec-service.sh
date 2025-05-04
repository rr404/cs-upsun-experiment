#!/usr/bin/env bash

echo "Reload Services"
systemctl --user daemon-reload

echo "Activating with user"
systemctl --user enable crowdsec.service

echo "Starting with user"
systemctl --user start crowdsec.service

# echo "Show current services"
# systemctl --user

echo "Show current services"
systemctl --user status crowdsec.service

echo "checking CAPI user"
echo $(head -n2 etc/crowdsec/online_api_credentials.yaml | tail -n1)

