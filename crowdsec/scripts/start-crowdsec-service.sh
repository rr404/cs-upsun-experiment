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

# http2udpRelay
# echo "Activating http2udpRelay with user"
# systemctl --user enable http2udpRelay.service

# echo "Starting http2udpRelay with user"
# systemctl --user start http2udpRelay.service

# echo "Show current service status"
# systemctl --user status http2udpRelay.service

# rsyslog
# echo "Show current services"
# systemctl --user status rsyslog.service


# echo "Activating rsyslog with user"
# systemctl --user enable rsyslog.service

# echo "Starting rsyslog with user"
# systemctl --user start rsyslog.service

# # echo "Show current services"
# # systemctl --user

# echo "Show current services"
# systemctl --user status rsyslog.service
