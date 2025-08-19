# CrowdSec Security Engine for Upsun

This is an off-the-shelf Upsun project to deploy a CrowdSec Security Engine and optional Remediation Components (bouncers) with minimal configuration from the user.

Default usage results in the CrowdSec Security Engine being installed with the Upsun collection for HTTP log parsing and intrusion detection.

## Build Flow Diagram

The following flowchart shows the deployment process and conditional bouncer installation based on environment variables:

┌───────┐
│ BUILD │
 ───────
    │
    ▼
[ init project hierarchy]
 > Create directory structure to host installed components
 > Copy systemd services
    │
    ▼
┌────────┐
│ DEPLOY │
 ────────
    │
    ▼
[ CrowdSec Setup ]
  // TODO check if working & fix : if no lock file named "${$TMP_DIR}/LAST_INSTALLED_${CROWDSEC_VERSION}${REINSTALL_SUFFIX}.lock"
    > download release based on CROWDSEC_VERSION
    > install and configure crowdsec in custom hierarchy (/app/cs/etc/crowdsec/ ++)
  > start crowdsec service
    │
    ▼
[ Bouncers setup ]
  if CLOUDFLARE_API_TOKENS variable found (CLOUDFLARE_API_TOKENS or/and FASTLY_API_TOKENS)
    > Download bouncer release
    > Install & config bouncer
        > copy config file template
        > update LAPI URL
        > link to crowdsec LAPI
    > Setup bouncer
        > Generate cloudflare specific config with command (it might deploy the worker code at that moment, not sure)
  // TODO run service

  if FASTLY_API_TOKENS variable found
    > setup python env
    >  Install & setup bouncer
        > installing bouncer package
        > copying binary to other folder
        > generating config
        > updateing config variables to work in this hierarchy
// TODO run service



#### 1. Version-Based Caching
```bash
# Implementation in scripts
CROWDSEC_VERSION_FILE="/app/cs/.installed_version"
CURRENT_VERSION=$(cat "$CROWDSEC_VERSION_FILE" 2>/dev/null || echo "none")

if [ "$CURRENT_VERSION" = "$CROWDSEC_VERSION" ] && [ -f "/app/cs/cscli" ]; then
    echo "CrowdSec $CROWDSEC_VERSION already installed, skipping download"
else
    # Perform installation
    echo "$CROWDSEC_VERSION" > "$CROWDSEC_VERSION_FILE"
fi
```

===================================================================
#### 2. Binary Existence Checks
```bash
# Skip installation if binaries exist and match expected version
if [ -f "/app/cs/cscli" ] && [ -f "/app/cs/crowdsec" ]; then
    INSTALLED_VERSION=$(/app/cs/cscli version --output json | jq -r '.version')
    if [ "$INSTALLED_VERSION" = "$CROWDSEC_VERSION" ]; then
        echo "CrowdSec binaries up to date"
        exit 0
    fi
fi
```

#### 3. Configuration Change Detection
```bash
# Use checksums to detect configuration changes
CONFIG_HASH=$(find /app/cs/etc/crowdsec -type f -name "*.yaml" -exec sha256sum {} \; | sort | sha256sum)
LAST_HASH=$(cat /app/cs/.config_hash 2>/dev/null || echo "none")

if [ "$CONFIG_HASH" != "$LAST_HASH" ]; then
    echo "Configuration changed, updating services"
    echo "$CONFIG_HASH" > /app/cs/.config_hash
    systemctl --user restart crowdsec
fi
```

### Force Rebuild Mechanisms

#### 1. Environment Variable Triggers
```bash
# Add to deployment scripts
if [ "$FORCE_REBUILD" = "true" ]; then
    echo "Force rebuild requested, removing existing installation"
    rm -rf /app/cs/
    rm -f /app/cs/.installed_version
    rm -f /app/cs/.config_hash
fi
```

#### 2. Version Upgrade Detection
```bash
# Automatic force rebuild on version changes
CROWDSEC_LATEST=$(curl -s https://api.github.com/repos/crowdsecurity/crowdsec/releases/latest | jq -r '.tag_name')
CROWDSEC_CURRENT=$(cat /app/cs/.installed_version 2>/dev/null || echo "none")

if [ "$CROWDSEC_LATEST" != "$CROWDSEC_CURRENT" ] && [ "$AUTO_UPGRADE" = "true" ]; then
    echo "New CrowdSec version available: $CROWDSEC_LATEST"
    export FORCE_REBUILD=true
fi
```

#### 3. Manual Force Rebuild Commands
```bash
# Utility script: scripts/force-rebuild.sh
#!/bin/bash
echo "Forcing complete rebuild..."
export FORCE_REBUILD=true
export FORCE_BOUNCER_REBUILD=true
./0_build.sh
./1_deploy-crowdsec.sh
./2_deploy-bouncer.sh
```

### Recommended Environment Variables for Optimization

#### Build Control Variables
- `FORCE_REBUILD=true` - Force complete rebuild regardless of existing installation
- `FORCE_BOUNCER_REBUILD=true` - Force bouncer reinstallation only
- `SKIP_VERSION_CHECK=true` - Skip version comparison checks
- `AUTO_UPGRADE=true` - Automatically upgrade to latest versions
- `PRESERVE_CONFIG=true` - Keep existing configuration during upgrades

#### Cache Control Variables  
- `ENABLE_BUILD_CACHE=true` - Enable build optimization features
- `CACHE_DIR=/app/cs/.cache` - Directory for build cache files
- `BUILD_TIMEOUT=300` - Maximum time to wait for build operations

### Implementation Priority

1. **Phase 1**: Version-based caching for CrowdSec engine
2. **Phase 2**: Bouncer-specific optimization with separate version tracking
3. **Phase 3**: Configuration change detection and selective service restarts
4. **Phase 4**: Advanced caching with dependency management

These optimizations would significantly reduce build times while maintaining the flexibility to force rebuilds when needed, such as security updates or major version changes.

## Development Commands

### CrowdSec Development
```bash
# Build systemd services and prepare environment
./scripts/0_build.sh

# Deploy CrowdSec engine
./scripts/1_deploy-crowdsec.sh

# Deploy bouncer (requires BOUNCER_TYPE env var: cloudflare or fastly)
./scripts/2_deploy-bouncer.sh

# Individual bouncer deployments
./scripts/2i_deploy-cloudflare-worker-bouncer.sh  # Binary-based bouncer
./scripts/2i_deploy-fastly-bouncer.sh            # Python pip-based bouncer
```

### Service Management
```bash
# CrowdSec service (systemd user services)
systemctl --user status crowdsec
systemctl --user start crowdsec
systemctl --user stop crowdsec
systemctl --user restart crowdsec

# CrowdSec CLI operations (from /app/cs directory)
/app/cs/cscli --config /app/cs/etc/crowdsec/config.yaml metrics
/app/cs/cscli --config /app/cs/etc/crowdsec/config.yaml decisions list
/app/cs/cscli --config /app/cs/etc/crowdsec/config.yaml bouncers list
```

## Environment Variables

### User Configuration (Optional Bouncer Setup)
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token for Worker bouncer
- `FASTLY_API_TOKEN` - Fastly API token(s) (comma-separated for multiple)

### Build Control
- `CROWDSEC_VERSION` - CrowdSec version to install (default: latest stable)
- `BOUNCER_TYPE` - Type of bouncer to deploy ("cloudflare" or "fastly")
- `FORCE_REBUILD` - Force complete rebuild (true/false)
- `AUTO_UPGRADE` - Automatically upgrade to latest versions (true/false)

## Architecture

- **Installation Directory**: `/app/cs/` (user-writable)
- **Configuration**: `/app/cs/etc/crowdsec/` (replicates `/etc/crowdsec`)
- **Binaries**: `/app/cs/bin/` (bouncer binaries)
- **Services**: systemd user services (no root privileges required)
- **Network**: HTTP upstream endpoint for log ingestion from other Upsun projects