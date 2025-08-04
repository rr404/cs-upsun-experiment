#!/usr/bin/env bash

echo "Deploying Cloudflare Bouncer"

# Source the environment variables first
if [ -f "${PLATFORM_APP_DIR}/crowdsec/.environment" ]; then
    source "${PLATFORM_APP_DIR}/crowdsec/.environment"
fi

# Ensure TMP_DIR is available for the script
if [ -z "${TMP_DIR:-}" ]; then
    TMP_DIR="/tmp"
fi

# Source the bouncer helper functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
BOUNCER_HELPER="${SCRIPT_DIR}/crowdsec/bouncers/cloudflare/_bouncer.sh"

if [ ! -f "$BOUNCER_HELPER" ]; then
    echo "Error: Bouncer helper script not found at $BOUNCER_HELPER" >&2
    exit 1
fi

source "$BOUNCER_HELPER"

# Set variables
CF_BOUNCER_VERSION="v0.0.14"
DOWNLOAD_URL="https://github.com/crowdsecurity/cs-cloudflare-worker-bouncer/releases/download/${CF_BOUNCER_VERSION}/${BOUNCER}-linux-amd64.tgz"

# Function: Download and extract the bouncer release
download_bouncer_release() {
    msg info "=== Téléchargement de la release ${BOUNCER} ${CF_BOUNCER_VERSION} ==="
    
    # Create necessary directories
    mkdir -p "$CONFIG_DIR" "$TMP_DIR"
    cd "$TMP_DIR"

    # Download if not already present
    if [ ! -f "${BOUNCER}-linux-amd64.tgz" ]; then
        msg info "Téléchargement de ${BOUNCER} ${CF_BOUNCER_VERSION}..."
        wget "$DOWNLOAD_URL" || {
            msg err "Échec du téléchargement du bouncer"
            exit 1
        }
        msg succ "Téléchargement terminé"
    else
        msg info "Archive déjà présente, réutilisation"
    fi

    # Extract
    msg info "Extraction du bouncer..."
    tar -xzf "${BOUNCER}-linux-amd64.tgz"
    cd "${BOUNCER}-${CF_BOUNCER_VERSION#v}/"
    
    # Update BIN_PATH for the helper functions
    BIN_PATH="./${BOUNCER}"
    
    msg succ "Release téléchargée et extraite avec succès"
}

# Function: Install binary and setup initial config
install_bouncer_binary() {
    msg info "=== Installation du binaire et configuration initiale ==="
    
    # Install the binary
    msg info "Installation du binaire bouncer..."
    upgrade_bin
    msg succ "Binaire installé: $BIN_PATH_INSTALLED"

    # Copy and setup config file if it doesn't exist
    if [ ! -f "$CONFIG" ]; then
        msg info "Configuration du fichier de configuration..."
        cp "config/${CONFIG_FILE}" "$CONFIG"
        chmod 0600 "$CONFIG"
        msg succ "Fichier de configuration créé: $CONFIG"
    else
        msg info "Fichier de configuration existant: $CONFIG"
    fi
}

# Function: Create API key with CrowdSec
create_api_key() {
    msg info "=== Création de la clé API CrowdSec ==="
    
    if set_api_key; then
        msg succ "Clé API CrowdSec configurée avec succès"
        return 0
    else
        msg warn "Échec de la configuration de la clé API - configuration manuelle requise"
        return 1
    fi
}

# Function: Update config with Cloudflare tokens and LAPI settings
update_bouncer_config() {
    msg info "=== Mise à jour de la configuration avec les tokens et paramètres ==="
    
    # Set Cloudflare API tokens if provided
    if [ -n "${CLOUDFLARE_API_TOKENS:-}" ]; then
        msg info "Configuration des tokens Cloudflare..."
        
        # Check what variable name the actual config file expects
        if grep -q "cloudflare_token:" "$CONFIG" 2>/dev/null; then
            set_config_var_value 'CLOUDFLARE_TOKEN' "$CLOUDFLARE_API_TOKENS"
        elif grep -q "cloudflare_api_token:" "$CONFIG" 2>/dev/null; then
            set_config_var_value 'CLOUDFLARE_API_TOKEN' "$CLOUDFLARE_API_TOKENS"
        elif grep -q "api_token:" "$CONFIG" 2>/dev/null; then
            set_config_var_value 'API_TOKEN' "$CLOUDFLARE_API_TOKENS"
        else
            # Fallback: try to add it manually to the config
            msg warn "Champ token cloudflare non trouvé dans la config, ajout manuel"
            echo "cloudflare_api_token: $CLOUDFLARE_API_TOKENS" >> "$CONFIG"
        fi
        msg succ "Tokens Cloudflare configurés"
    else
        msg warn "CLOUDFLARE_API_TOKENS non défini. Configuration manuelle requise dans $CONFIG"
    fi

    # Set the local LAPI URL
    msg info "Configuration de l'URL LAPI locale..."
    if grep -q "lapi_url:" "$CONFIG" 2>/dev/null; then
        set_local_lapi_url 'LAPI_URL'
        msg succ "URL LAPI configurée"
    elif grep -q "url:" "$CONFIG" 2>/dev/null; then
        set_local_lapi_url 'URL'
        msg succ "URL LAPI configurée"
    else
        msg warn "Champ URL LAPI non trouvé dans la config"
    fi

    # Update any port configurations
    msg info "Mise à jour des configurations de port..."
    set_local_port
    msg succ "Configuration mise à jour avec succès"
}

# Function: Test the final configuration
test_bouncer_config() {
    msg info "=== Test de la configuration finale ==="
    
    if [ -x "$BIN_PATH_INSTALLED" ]; then
        msg info "Test de la configuration..."
        if "$BIN_PATH_INSTALLED" -c "$CONFIG" -T >/dev/null 2>&1; then
            msg succ "Test de configuration réussi"
            return 0
        else
            msg warn "Test de configuration échoué - vérifiez $CONFIG manuellement"
            msg info "Vous pouvez tester manuellement avec: $BIN_PATH_INSTALLED -c $CONFIG -T"
            return 1
        fi
    else
        msg warn "Binaire non exécutable, impossible de tester la configuration"
        return 1
    fi
}

# Function: Display deployment summary
show_deployment_summary() {
    msg info "=== Résumé du déploiement ==="
    msg info "Fichier de configuration: $CONFIG"
    msg info "Binaire: $BIN_PATH_INSTALLED"
    msg info "Version: $CF_BOUNCER_VERSION"
    
    if [ -n "${CLOUDFLARE_API_TOKENS:-}" ]; then
        msg info "Tokens Cloudflare: Configurés"
    else
        msg warn "Tokens Cloudflare: Non configurés"
    fi
}

# Main deployment flow
main() {
    msg info "Début du déploiement du bouncer Cloudflare"
    
    # Step 1: Download bouncer release
    download_bouncer_release
    
    # Step 2: Install binary and setup initial config
    install_bouncer_binary
    
    # Step 3: Create API key
    if ! create_api_key; then
        msg warn "Continuant malgré l'échec de création de la clé API..."
    fi
    
    # Step 4: Update config with tokens and settings
    update_bouncer_config
    
    # Step 5: Test configuration
    if test_bouncer_config; then
        msg succ "Bouncer Cloudflare déployé avec succès!"
    else
        msg warn "Déploiement terminé avec des avertissements"
    fi
    
    # Step 6: Show summary
    show_deployment_summary
}

# Execute main deployment
main "$@"