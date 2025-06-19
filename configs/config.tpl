# Configuration générée automatiquement par Terraform
# Date: $(date)
# Projet: Interconnexion AWS-Azure

# === INFORMATIONS AWS ===
AWS_INSTANCE_IP="${aws_instance_ip}"
AWS_INSTANCE_ID="${aws_instance_id}"
AWS_VPC_ID="${aws_vpc_id}"
AWS_SUBNET_ID="${aws_subnet_id}"
AWS_SECURITY_GROUP_ID="${aws_sg_id}"

# === INFORMATIONS AZURE ===
AZURE_SQL_SERVER_FQDN="${azure_server_fqdn}"
AZURE_DATABASE_NAME="${azure_db_name}"
AZURE_ADMIN_USER="${azure_admin_user}"
AZURE_ADMIN_PASSWORD="${azure_admin_pass}"

# === INFORMATIONS S3 ===
S3_BUCKET_NAME="${s3_bucket_name}"

# === COMMANDES UTILES ===
# Connexion SSH
# ssh -i tp-aws-azure.pem ec2-user@${aws_instance_ip}

# Test de connexion SQL
# /opt/mssql-tools/bin/sqlcmd -S ${azure_server_fqdn} -U ${azure_admin_user} -P '${azure_admin_pass}' -Q "SELECT GETDATE();"

# Test de connectivité réseau
# telnet ${azure_server_fqdn} 1433