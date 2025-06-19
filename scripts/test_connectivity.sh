#!/bin/bash

# Script de test de connectivité AWS-Azure
# Auteur: FIENI DANNIE INNOCENT JUNIOR
# Usage: ./test_connectivity.sh [config_file]

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration par défaut
CONFIG_FILE="${1:-deployment_config.env}"

# Fonction d'affichage
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCÈS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERREUR]${NC} $1"
}

# Vérifier si le fichier de configuration existe
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Fichier de configuration '$CONFIG_FILE' introuvable"
    echo "Usage: $0 [config_file]"
    exit 1
fi

# Charger la configuration
source "$CONFIG_FILE"

echo -e "${BLUE}=== Test de Connectivité AWS-Azure ===${NC}"
echo "Configuration chargée depuis: $CONFIG_FILE"
echo

# Test 1: Vérifier la résolution DNS du serveur Azure
log_info "Test 1: Résolution DNS du serveur Azure SQL"
if nslookup "$AZURE_SQL_SERVER_FQDN" >/dev/null 2>&1; then
    log_success "Résolution DNS réussie pour $AZURE_SQL_SERVER_FQDN"
    
    # Obtenir l'adresse IP
    AZURE_IP=$(nslookup "$AZURE_SQL_SERVER_FQDN" | grep -A1 "Name:" | tail -n1 | awk '{print $2}')
    echo "  → Adresse IP résolue: $AZURE_IP"
else
    log_error "Échec de la résolution DNS"
    exit 1
fi
echo

# Test 2: Test de connectivité réseau (port 1433)
log_info "Test 2: Connectivité réseau vers le port SQL (1433)"
if command -v telnet >/dev/null 2>&1; then
    # Utiliser telnet si disponible
    if timeout 10 telnet "$AZURE_SQL_SERVER_FQDN" 1433 >/dev/null 2>&1; then
        log_success "Port 1433 accessible sur $AZURE_SQL_SERVER_FQDN"
    else
        log_warning "Port 1433 non accessible ou timeout"
    fi
elif command -v nc >/dev/null 2>&1; then
    # Utiliser netcat si telnet n'est pas disponible
    if timeout 10 nc -z "$AZURE_SQL_SERVER_FQDN" 1433 >/dev/null 2>&1; then
        log_success "Port 1433 accessible sur $AZURE_SQL_SERVER_FQDN"
    else
        log_warning "Port 1433 non accessible ou timeout"
    fi
else
    log_warning "Ni telnet ni netcat disponible pour tester la connectivité"
fi
echo

# Test 3: Test SSL/TLS
log_info "Test 3: Vérification du certificat SSL/TLS"
if command -v openssl >/dev/null 2>&1; then
    if echo | timeout 10 openssl s_client -connect "$AZURE_SQL_SERVER_FQDN:1433" -starttls mssql >/dev/null 2>&1; then
        log_success "Certificat SSL/TLS valide"
    else
        log_warning "Problème avec le certificat SSL/TLS ou la connexion"
    fi
else
    log_warning "OpenSSL non disponible pour tester SSL/TLS"
fi
echo

# Test 4: Test de connexion SQL (si sqlcmd est disponible)
log_info "Test 4: Test de connexion à la base de données"
if command -v sqlcmd >/dev/null 2>&1; then
    # Test de connexion avec une requête simple
    if sqlcmd -S "$AZURE_SQL_SERVER_FQDN" -U "$AZURE_ADMIN_USER" -P "$AZURE_ADMIN_PASSWORD" -Q "SELECT GETDATE() AS CurrentDateTime;" -h -1 >/dev/null 2>&1; then
        log_success "Connexion SQL réussie et requête exécutée"
        
        # Exécuter une requête de test et afficher le résultat
        echo "  → Test de requête:"
        RESULT=$(sqlcmd -S "$AZURE_SQL_SERVER_FQDN" -U "$AZURE_ADMIN_USER" -P "$AZURE_ADMIN_PASSWORD" -Q "SELECT GETDATE() AS CurrentDateTime;" -h -1 2>/dev/null | grep -v "rows affected" | tail -n +2)
        echo "  → Date/Heure du serveur: $RESULT"
    else
        log_error "Échec de la connexion SQL"
        echo "  → Vérifiez les paramètres de connexion et les règles de pare-feu"
    fi
elif [[ -f "/opt/mssql-tools/bin/sqlcmd" ]]; then
    # Essayer le chemin complet
    if /opt/mssql-tools/bin/sqlcmd -S "$AZURE_SQL_SERVER_FQDN" -U "$AZURE_ADMIN_USER" -P "$AZURE_ADMIN_PASSWORD" -Q "SELECT GETDATE() AS CurrentDateTime;" -h -1 >/dev/null 2>&1; then
        log_success "Connexion SQL réussie et requête exécutée"
        
        RESULT=$(/opt/mssql-tools/bin/sqlcmd -S "$AZURE_SQL_SERVER_FQDN" -U "$AZURE_ADMIN_USER" -P "$AZURE_ADMIN_PASSWORD" -Q "SELECT GETDATE() AS CurrentDateTime;" -h -1 2>/dev/null | grep -v "rows affected" | tail -n +2)
        echo "  → Date/Heure du serveur: $RESULT"
    else
        log_error "Échec de la connexion SQL"
    fi
else
    log_warning "sqlcmd non disponible pour tester la connexion SQL"
    echo "  → Installez mssql-tools: sudo yum install -y mssql-tools"
fi
echo

# Test 5: Vérification des règles de pare-feu
log_info "Test 5: Vérification de l'IP publique actuelle"
CURRENT_IP=$(curl -s http://checkip.amazonaws.com/ || curl -s http://ifconfig.me/ || echo "Impossible de déterminer")
echo "  → IP publique actuelle: $CURRENT_IP"

if [[ "$CURRENT_IP" != "Impossible de déterminer" ]]; then
    log_info "Assurez-vous que cette IP est autorisée dans le pare-feu Azure SQL"
else
    log_warning "Impossible de déterminer l'IP publique"
fi
echo

# Test 6: Test de performance réseau (ping)
log_info "Test 6: Test de latence réseau"
if command -v ping >/dev/null 2>&1; then
    if PING_RESULT=$(ping -c 4 "$AZURE_SQL_SERVER_FQDN" 2>/dev/null); then
        AVG_TIME=$(echo "$PING_RESULT" | tail -1 | awk -F'/' '{print $5}')
        log_success "Ping réussi - Latence moyenne: ${AVG_TIME}ms"
    else
        log_warning "Ping échoué (normal pour certains serveurs Azure)"
    fi
else
    log_warning "Commande ping non disponible"
fi
echo

# Résumé
echo -e "${BLUE}=== Résumé des Tests ===${NC}"
echo "Serveur Azure SQL: $AZURE_SQL_SERVER_FQDN"
echo "Base de données: $AZURE_DATABASE_NAME"
echo "Utilisateur: $AZURE_ADMIN_USER"
echo

# Génération d'un rapport
REPORT_FILE="connectivity_report_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "Rapport de Connectivité AWS-Azure"
    echo "================================="
    echo "Date: $(date)"
    echo "Serveur: $AZURE_SQL_SERVER_FQDN"
    echo "Base de données: $AZURE_DATABASE_NAME"
    echo "IP publique testée: $CURRENT_IP"
    echo
    echo "Tests effectués:"
    echo "- Résolution DNS"
    echo "- Connectivité port 1433"
    echo "- Vérification SSL/TLS"
    echo "- Connexion SQL"
    echo "- Latence réseau"
} > "$REPORT_FILE"

log_success "Rapport sauvegardé dans: $REPORT_FILE"

# Commandes utiles
echo
echo -e "${BLUE}=== Commandes Utiles ===${NC}"
echo "Connexion SSH à l'instance EC2:"
echo "  ssh -i tp-aws-azure.pem ec2-user@$AWS_INSTANCE_IP"
echo
echo "Test de connexion SQL:"
echo "  sqlcmd -S $AZURE_SQL_SERVER_FQDN -U $AZURE_ADMIN_USER -P '$AZURE_ADMIN_PASSWORD' -Q \"SELECT GETDATE();\""
echo
echo "Test de connectivité réseau:"
echo "  telnet $AZURE_SQL_SERVER_FQDN 1433"