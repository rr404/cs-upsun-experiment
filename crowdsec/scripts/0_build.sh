#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# systemd files setup
echo "Create Systemd user folder structure..."
mkdir -p ~/.config/systemd/user/multi-user.target.wants/

echo "Copy Systemd user services..."
cp -R scripts/systemd.d/* ~/.config/systemd/user/
cp -R scripts/systemd.d/* ~/.config/systemd/user/multi-user.target.wants/

# http2udpRelay service build
cd ${SCRIPTS_DIR}/bin/http2udpRelay
echo "Building http2udpRelay..."
go build -o http2udpRelay main.go