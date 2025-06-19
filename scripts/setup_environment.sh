#!/bin/bash

echo "🔧 Configuration de l'environnement..."

# Vérification des prérequis
echo "Vérification des outils requis..."

# Terraform
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform n'est pas installé"
    exit 1
fi

# AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI n'est pas installé"
    exit 1
fi

# Azure CLI
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI n'est pas installé"
    exit 1
fi

echo "✅ Tous les outils sont installés"

# Configuration des credentials
echo "Configuration des credentials..."

# Vérification AWS
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials non configurés"
    echo "Exécute: aws configure"
    exit 1
fi

# Vérification Azure
if ! az account show &> /dev/null; then
    echo "❌ Azure credentials non configurés"
    echo "Exécute: az login"
    exit 1
fi

echo "✅ Credentials configurés"

# Initialisation Terraform
echo "Initialisation de Terraform..."
cd terraform
terraform init

echo "✅ Environnement prêt!"