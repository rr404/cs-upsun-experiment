#!/bin/bash

usage() {
	echo "Usage:"
	echo "    $0 -h                             Display this help message."
	echo "    $0 /setup/dir                     Setup CrowdSec in '/setup/dir' folder"
	exit 0
}

# check if first arg exist and is a directory
if [ -z "$1" ]; then
    echo "Need to provide setup directory"
    exit 1
fi

BASE=$1

DATA_DIR="$BASE/data"

LOG_DIR="$BASE/logs/"

CONFIG_DIR="$BASE/config"
CONFIG_FILE="$BASE/config.yaml"
# CSCLI_DIR="$CONFIG_DIR/crowdsec-cli"
# PARSER_DIR="$CONFIG_DIR/parsers"
# PARSER_S00="$PARSER_DIR/s00-raw"
# PARSER_S01="$PARSER_DIR/s01-parse"
# PARSER_S02="$PARSER_DIR/s02-enrich"
# SCENARIOS_DIR="$CONFIG_DIR/scenarios"
# POSTOVERFLOWS_DIR="$CONFIG_DIR/postoverflows"
HUB_DIR="$BASE/hub"
PLUGINS="http slack splunk email sentinel"
PLUGINS_DIR="plugins"
NOTIF_DIR="notifications"

log_info() {
	msg=$1
	date=$(date +%x:%X)
	echo -e "[$date][INFO] $msg"
}

create_tree() {
	mkdir -p "$BASE"
	mkdir -p "$DATA_DIR"
	mkdir -p "$LOG_DIR"
	mkdir -p "$CONFIG_DIR"
	# mkdir -p "$PARSER_DIR"
	# mkdir -p "$PARSER_S00"
	# mkdir -p "$PARSER_S01"
	# mkdir -p "$PARSER_S02"
	# mkdir -p "$SCENARIOS_DIR"
	# mkdir -p "$POSTOVERFLOWS_DIR"
	#mkdir -p "$CSCLI_DIR"
	mkdir -p "$HUB_DIR"
	mkdir -p "$CONFIG_DIR/$NOTIF_DIR/$plugin"
	mkdir -p "$BASE/$PLUGINS_DIR"
}

copy_files() {
	cp "./config/profiles.yaml" "$BASE"
	cp "./config/simulation.yaml" "$BASE"
	cp "./cmd/crowdsec/crowdsec" "$BASE"
	cp "./cmd/crowdsec-cli/cscli" "$BASE"
	cp -r "./config/patterns" "$BASE"
	cp "./config/acquis.yaml" "$BASE"
    cp "./config/config.yaml" "$BASE"
    cp "./config/config.yaml" "$BASE/config.yaml.orig" 
	touch "$BASE"/local_api_credentials.yaml
	touch "$BASE"/online_api_credentials.yaml
	for plugin in $PLUGINS
	do
		cp cmd/notification-$plugin/notification-$plugin $BASE/$PLUGINS_DIR/notification-$plugin
		cp cmd/notification-$plugin/$plugin.yaml $CONFIG_DIR/$NOTIF_DIR/$plugin.yaml
	done
}

setup_config_file() {
    sed -i "s|/etc/crowdsec|${BASE}|" config.yaml
    sed -i "s|/var/lib/crowdsec|${BASE}|" config.yaml
    sed -i "s|/usr/local/lib/crowdsec|${BASE}|" config.yaml
    sed -i "s|/var/log|${BASE}/log|" config.yaml
}

setup_api() {
	$BASE/cscli -c "$CONFIG_FILE" capi register
    $BASE/cscli -c "$CONFIG_FILE" machines add --auto --force
}

setup_collections() {
	$BASE/cscli -c "$CONFIG_FILE" hub update
	$BASE/cscli -c "$CONFIG_FILE" collections install crowdsecurity/linux
}

main() {
	log_info "Creating test tree in $BASE"
	create_tree
	log_info "Tree created"
	log_info "Copying needed files for tests environment"
	copy_files
	log_info "Files copied"
	CURRENT_PWD=$(pwd)
	cd $BASE
    log_info "Setting up configuration files"
    setup_config_file
    log_info "Setting up APIs"
	setup_api
    log_info "Setting up Hub & Linux Collection"
	setup_collections
	cd $CURRENT_PWD
	log_info "Environment is ready in $BASE"
}


main