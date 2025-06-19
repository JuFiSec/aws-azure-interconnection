# Configuration Terraform pour l'interconnexion AWS-Azure
# Auteur: FIENI DANNIE INNOCENT JUNIOR
# Date: 16 Juin 2025

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Configuration des providers
provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}

# Variables
variable "aws_region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "azure_region" {
  description = "Région Azure"
  type        = string
  default     = "West Europe"
}

variable "project_name" {
  description = "Nom du projet"
  type        = string
  default     = "tp-aws-azure"
}

variable "vpc_cidr" {
  description = "CIDR block du VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block du sous-réseau"
  type        = string
  default     = "10.20.1.0/24"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "Nom de la clé SSH"
  type        = string
  default     = "tp-aws-azure"
}

variable "db_admin_username" {
  description = "Nom d'utilisateur admin de la base de données"
  type        = string
  default     = "tpuser"
}

variable "db_admin_password" {
  description = "Mot de passe admin de la base de données"
  type        = string
  default     = "TP2025sql!"
  sensitive   = true
}

# Données locales
locals {
  common_tags = {
    Project   = var.project_name
    CreatedBy = "Terraform"
    Owner     = "FIENI DANNIE INNOCENT JUNIOR"
  }
}

# Récupérer l'IP publique actuelle
data "http" "current_ip" {
  url = "http://checkip.amazonaws.com/"
}

locals {
  current_ip = chomp(data.http.current_ip.response_body)
}

# Récupérer l'AMI Amazon Linux 2 la plus récente
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# === RESSOURCES AWS ===

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# Sous-réseau public
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

# Table de routage
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Association table de routage
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instance"
  vpc_id      = aws_vpc.main.id

  # SSH depuis l'IP actuelle
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.current_ip}/32"]
    description = "SSH access"
  }

  # SQL Server port pour Azure
  egress {
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SQL Server to Azure"
  }

  # HTTP/HTTPS pour les mises à jour
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound"
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound"
  }

  # DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-sg"
  })
}

# Instance EC2
resource "aws_instance" "main" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id              = aws_subnet.public.id

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    # Installation des outils SQL Server
    curl https://packages.microsoft.com/config/rhel/7/prod.repo > /etc/yum.repos.d/msprod.repo
    yum install -y mssql-tools unixODBC-devel
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> /home/ec2-user/.bash_profile
    # Installation de telnet pour les tests
    yum install -y telnet
    # Installation de git pour cloner le repository
    yum install -y git
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-instance"
  })
}

# Bucket S3 pour la documentation (bonus)
resource "aws_s3_bucket" "documentation" {
  bucket = "${var.project_name}-doc-${random_string.bucket_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-documentation"
  })
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_public_access_block" "documentation" {
  bucket = aws_s3_bucket.documentation.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "documentation" {
  bucket = aws_s3_bucket.documentation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PublicReadGetObject"
        Effect = "Allow"
        Principal = "*"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.documentation.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.documentation]
}

# Upload README vers S3
resource "aws_s3_object" "readme" {
  bucket       = aws_s3_bucket.documentation.id
  key          = "README.md"
  content      = file("${path.module}/README.md")
  content_type = "text/markdown"

  tags = local.common_tags
}

# CloudWatch Alarm (bonus)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = []

  dimensions = {
    InstanceId = aws_instance.main.id
  }

  tags = local.common_tags
}

# === RESSOURCES AZURE ===

# Groupe de ressources Azure
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-rg"
  location = var.azure_region

  tags = local.common_tags
}

# Serveur SQL Azure
resource "azurerm_mssql_server" "main" {
  name                         = "${var.project_name}-sql-server-${random_string.sql_suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.db_admin_username
  administrator_login_password = var.db_admin_password
  minimum_tls_version          = "1.2"

  tags = local.common_tags
}

resource "random_string" "sql_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Base de données Azure SQL
resource "azurerm_mssql_database" "main" {
  name           = "${var.project_name}-database"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 2
  sku_name       = "Basic"
  zone_redundant = false

  tags = local.common_tags
}

# Règle de pare-feu pour l'instance EC2
resource "azurerm_mssql_firewall_rule" "ec2_access" {
  name             = "AllowEC2Instance"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = aws_instance.main.public_ip
  end_ip_address   = aws_instance.main.public_ip
}

# Règle de pare-feu pour l'IP locale (pour les tests)
resource "azurerm_mssql_firewall_rule" "local_access" {
  name             = "AllowLocalIP"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = local.current_ip
  end_ip_address   = local.current_ip
}

# Logic App Azure (bonus)
resource "azurerm_logic_app_workflow" "main" {
  name                = "${var.project_name}-logic-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# === OUTPUTS ===

output "aws_instance_public_ip" {
  description = "IP publique de l'instance EC2"
  value       = aws_instance.main.public_ip
}

output "aws_instance_id" {
  description = "ID de l'instance EC2"
  value       = aws_instance.main.id
}

output "aws_vpc_id" {
  description = "ID du VPC AWS"
  value       = aws_vpc.main.id
}

output "azure_sql_server_fqdn" {
  description = "FQDN du serveur SQL Azure"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "azure_database_name" {
  description = "Nom de la base de données Azure"
  value       = azurerm_mssql_database.main.name
}

output "s3_bucket_name" {
  description = "Nom du bucket S3"
  value       = aws_s3_bucket.documentation.id
}

output "s3_readme_url" {
  description = "URL du README sur S3"
  value       = "https://${aws_s3_bucket.documentation.bucket}.s3.${var.aws_region}.amazonaws.com/README.md"
}

output "ssh_connection_command" {
  description = "Commande pour se connecter en SSH"
  value       = "ssh -i ${var.key_name}.pem ec2-user@${aws_instance.main.public_ip}"
}

output "sql_connection_command" {
  description = "Commande pour tester la connexion SQL"
  value       = "/opt/mssql-tools/bin/sqlcmd -S ${azurerm_mssql_server.main.fully_qualified_domain_name} -U ${var.db_admin_username} -P '${var.db_admin_password}' -Q \"SELECT GETDATE();\""
  sensitive   = true
}

# Création d'un fichier de configuration pour les scripts
resource "local_file" "config" {
  content = templatefile("${path.module}/config.tpl", {
    aws_instance_ip    = aws_instance.main.public_ip
    aws_instance_id    = aws_instance.main.id
    aws_vpc_id         = aws_vpc.main.id
    aws_subnet_id      = aws_subnet.public.id
    aws_sg_id          = aws_security_group.ec2.id
    azure_server_fqdn  = azurerm_mssql_server.main.fully_qualified_domain_name
    azure_db_name      = azurerm_mssql_database.main.name
    azure_admin_user   = var.db_admin_username
    azure_admin_pass   = var.db_admin_password
    s3_bucket_name     = aws_s3_bucket.documentation.id
  })
  filename = "${path.module}/deployment_config.env"
}