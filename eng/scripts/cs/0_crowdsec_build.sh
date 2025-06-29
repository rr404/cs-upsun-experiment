#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Setting up Service Files for CrowdSec
echo "Create Systemd user folder structure..."
echo "testing env variable: VAR_DIR=${VAR_DIR}"
mkdir -p ~/.config/systemd/user/multi-user.target.wants/

echo "Copy Systemd user services..."
cp -R scripts/cs/systemd.d/* ~/.config/systemd/user/
cp -R scripts/cs/systemd.d/* ~/.config/systemd/user/multi-user.target.wants/