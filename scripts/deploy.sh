#!/bin/bash

# Script de déploiement automatisé - Interconnexion AWS et Azure
# Auteur: FIENI DANNIE INNOCENT JUNIOR
# Date: 16 Juin 2025

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="eu-west-3"
VPC_CIDR="10.20.0.0/16"
SUBNET_CIDR="10.20.1.0/24"
INSTANCE_TYPE="t2.micro"
KEY_NAME="tp-aws-azure"

# Azure
RESOURCE_GROUP="rg-tp-aws-azure"
SERVER_NAME="srv-tp-fieni"
DATABASE_NAME="tp-database"
ADMIN_USER="tpuser"
ADMIN_PASSWORD="TP2025sql!"

echo -e "${BLUE}=== Déploiement Interconnexion AWS-Azure ===${NC}"

# Fonction d'affichage des étapes
log_step() {
    echo -e "${YELLOW}[ÉTAPE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCÈS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERREUR]${NC} $1"
}

# Vérifier les prérequis
check_prerequisites() {
    log_step "Vérification des prérequis..."
    
    # Vérifier AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI n'est pas installé"
        exit 1
    fi
    
    # Vérifier Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI n'est pas installé"
        exit 1
    fi
    
    # Vérifier l'authentification AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI n'est pas configuré"
        exit 1
    fi
    
    # Vérifier l'authentification Azure
    if ! az account show &> /dev/null; then
        log_error "Azure CLI n'est pas connecté"
        exit 1
    fi
    
    log_success "Tous les prérequis sont satisfaits"
}

# Déploiement AWS
deploy_aws() {
    log_step "Déploiement de l'infrastructure AWS..."
    
    # Créer le VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block $VPC_CIDR \
        --region $AWS_REGION \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=tp-aws-azure-vpc}]" \
        --query 'Vpc.VpcId' \
        --output text)
    
    log_success "VPC créé: $VPC_ID"
    
    # Activer DNS hostname
    aws ec2 modify-vpc-attribute \
        --vpc-id $VPC_ID \
        --enable-dns-hostnames \
        --region $AWS_REGION
    
    # Créer Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --region $AWS_REGION \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=tp-igw}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    
    # Attacher IGW au VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID \
        --region $AWS_REGION
    
    log_success "Internet Gateway créé et attaché: $IGW_ID"
    
    # Créer le sous-réseau public
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $SUBNET_CIDR \
        --availability-zone "${AWS_REGION}c" \
        --region $AWS_REGION \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=tp-public-subnet}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    log_success "Sous-réseau créé: $SUBNET_ID"
    
    # Créer table de routage
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --region $AWS_REGION \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=tp-public-rt}]" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    # Ajouter route vers Internet
    aws ec2 create-route \
        --route-table-id $ROUTE_TABLE_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID \
        --region $AWS_REGION
    
    # Associer le sous-réseau à la table de routage
    aws ec2 associate-route-table \
        --subnet-id $SUBNET_ID \
        --route-table-id $ROUTE_TABLE_ID \
        --region $AWS_REGION
    
    log_success "Table de routage configurée"
    
    # Créer Security Group
    SG_ID=$(aws ec2 create-security-group \
        --group-name tp-ec2-sg \
        --description "Security group for AWS-Azure interconnection" \
        --vpc-id $VPC_ID \
        --region $AWS_REGION \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=tp-ec2-sg}]" \
        --query 'GroupId' \
        --output text)
    
    # Obtenir l'IP publique pour SSH
    MY_IP=$(curl -s http://checkip.amazonaws.com/)
    
    # Règle SSH
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr "${MY_IP}/32" \
        --region $AWS_REGION
    
    # Règle SQL (pour Azure)
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 1433 \
        --cidr 0.0.0.0/0 \
        --region $AWS_REGION
    
    log_success "Security Group créé: $SG_ID"
    
    # Lancer l'instance EC2
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $(aws ec2 describe-images \
            --owners amazon \
            --filters "Name=name,Values=amzn2-ami-hvm-*" "Name=architecture,Values=x86_64" \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --region $AWS_REGION \
            --output text) \
        --count 1 \
        --instance-type $INSTANCE_TYPE \
        --key-name $KEY_NAME \
        --security-group-ids $SG_ID \
        --subnet-id $SUBNET_ID \
        --associate-public-ip-address \
        --region $AWS_REGION \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=tp-aws-azure-instance}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    log_success "Instance EC2 lancée: $INSTANCE_ID"
    
    # Attendre que l'instance soit en cours d'exécution
    log_step "Attente du démarrage de l'instance..."
    aws ec2 wait instance-running \
        --instance-ids $INSTANCE_ID \
        --region $AWS_REGION
    
    # Récupérer l'IP publique
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $AWS_REGION \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    log_success "Infrastructure AWS déployée. IP publique: $PUBLIC_IP"
    
    # Sauvegarder les informations
    echo "AWS_VPC_ID=$VPC_ID" > aws_info.txt
    echo "AWS_SUBNET_ID=$SUBNET_ID" >> aws_info.txt
    echo "AWS_INSTANCE_ID=$INSTANCE_ID" >> aws_info.txt
    echo "AWS_PUBLIC_IP=$PUBLIC_IP" >> aws_info.txt
    echo "AWS_SECURITY_GROUP_ID=$SG_ID" >> aws_info.txt
}

# Déploiement Azure
deploy_azure() {
    log_step "Déploiement de l'infrastructure Azure..."
    
    # Créer le groupe de ressources
    az group create \
        --name $RESOURCE_GROUP \
        --location westeurope
    
    log_success "Groupe de ressources créé: $RESOURCE_GROUP"
    
    # Créer le serveur SQL
    az sql server create \
        --name $SERVER_NAME \
        --resource-group $RESOURCE_GROUP \
        --location westeurope \
        --admin-user $ADMIN_USER \
        --admin-password $ADMIN_PASSWORD
    
    log_success "Serveur SQL créé: $SERVER_NAME"
    
    # Créer la base de données
    az sql db create \
        --resource-group $RESOURCE_GROUP \
        --server $SERVER_NAME \
        --name $DATABASE_NAME \
        --service-objective Basic
    
    log_success "Base de données créée: $DATABASE_NAME"
    
    # Configurer le pare-feu (si l'IP AWS est disponible)
    if [ -f aws_info.txt ]; then
        AWS_IP=$(grep AWS_PUBLIC_IP aws_info.txt | cut -d'=' -f2)
        az sql server firewall-rule create \
            --resource-group $RESOURCE_GROUP \
            --server $SERVER_NAME \
            --name "Allow-AWS-EC2" \
            --start-ip-address $AWS_IP \
            --end-ip-address $AWS_IP
        
        log_success "Règle de pare-feu configurée pour l'IP AWS: $AWS_IP"
    fi
    
    # Sauvegarder les informations Azure
    echo "AZURE_RESOURCE_GROUP=$RESOURCE_GROUP" > azure_info.txt
    echo "AZURE_SERVER_NAME=$SERVER_NAME" >> azure_info.txt
    echo "AZURE_DATABASE_NAME=$DATABASE_NAME" >> azure_info.txt
    echo "AZURE_ADMIN_USER=$ADMIN_USER" >> azure_info.txt
}

# Test de connectivité
test_connectivity() {
    log_step "Test de connectivité..."
    
    if [ ! -f aws_info.txt ] || [ ! -f azure_info.txt ]; then
        log_error "Fichiers d'information manquants"
        return 1
    fi
    
    source aws_info.txt
    source azure_info.txt
    
    echo -e "${BLUE}Informations de connexion:${NC}"
    echo "AWS Instance IP: $AWS_PUBLIC_IP"
    echo "Azure SQL Server: ${AZURE_SERVER_NAME}.database.windows.net"
    echo "Database: $AZURE_DATABASE_NAME"
    echo "Username: $AZURE_ADMIN_USER"
    
    log_success "Déploiement terminé avec succès!"
}

# Fonction de nettoyage
cleanup() {
    log_step "Nettoyage des ressources..."
    
    # Nettoyage AWS
    if [ -f aws_info.txt ]; then
        source aws_info.txt
        
        # Terminer l'instance
        aws ec2 terminate-instances --instance-ids $AWS_INSTANCE_ID --region $AWS_REGION
        aws ec2 wait instance-terminated --instance-ids $AWS_INSTANCE_ID --region $AWS_REGION
        
        # Supprimer les ressources réseau
        aws ec2 delete-security-group --group-id $AWS_SECURITY_GROUP_ID --region $AWS_REGION
        aws ec2 detach-internet-gateway --internet-gateway-id $AWS_IGW_ID --vpc-id $AWS_VPC_ID --region $AWS_REGION
        aws ec2 delete-internet-gateway --internet-gateway-id $AWS_IGW_ID --region $AWS_REGION
        aws ec2 delete-subnet --subnet-id $AWS_SUBNET_ID --region $AWS_REGION
        aws ec2 delete-vpc --vpc-id $AWS_VPC_ID --region $AWS_REGION
        
        rm aws_info.txt
    fi
    
    # Nettoyage Azure
    if [ -f azure_info.txt ]; then
        source azure_info.txt
        az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait
        rm azure_info.txt
    fi
    
    log_success "Nettoyage terminé"
}

# Menu principal
case "${1:-deploy}" in
    "deploy")
        check_prerequisites
        deploy_aws
        deploy_azure
        test_connectivity
        ;;
    "cleanup")
        cleanup
        ;;
    "test")
        test_connectivity
        ;;
    *)
        echo "Usage: $0 {deploy|cleanup|test}"
        echo "  deploy  - Déployer l'infrastructure complète"
        echo "  cleanup - Supprimer toutes les ressources"
        echo "  test    - Tester la connectivité"
        exit 1
        ;;
esac