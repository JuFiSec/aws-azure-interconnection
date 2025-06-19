#!/bin/bash

echo "🧹 Nettoyage de l'infrastructure AWS-Azure..."

# Nettoyage Terraform
echo "Destruction de l'infrastructure Terraform..."
cd terraform
terraform destroy -auto-approve

# Nettoyage des fichiers temporaires
echo "Nettoyage des fichiers temporaires..."
rm -f *.log
rm -f *.backup
rm -rf .terraform/

echo "✅ Nettoyage terminé!"