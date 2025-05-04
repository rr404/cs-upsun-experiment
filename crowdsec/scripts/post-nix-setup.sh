#!/usr/bin/env bash

echo $(ls -p .local/share/crowdsec/config)
chmod +wx .local/share/crowdsec/config/config.yaml