#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Pre-requisites sourcing and variables setup
## Source the environment variables first
if [ -f "${PLATFORM_APP_DIR}/.environment" ]; then
    source "${PLATFORM_APP_DIR}/.environment"
fi

# Systemd files setup
echo "Create Systemd user folder structure..."
mkdir -p ~/.config/systemd/user/multi-user.target.wants/

echo "Copy Systemd user services..."
cp -R scripts/systemd.d/* ~/.config/systemd/user/
cp -R scripts/systemd.d/* ~/.config/systemd/user/multi-user.target.wants/

# Ensure pip is available for Python3
echo "Installing/upgrading pip..."
python3.13 -m pip install --upgrade pip