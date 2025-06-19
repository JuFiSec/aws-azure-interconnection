output "ec2_public_ip" {
  description = "Public IP of EC2 instance"
  value       = aws_instance.tp_instance.public_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.tp_vpc.id
}

output "azure_sql_server_fqdn" {
  description = "Azure SQL Server FQDN"
  value       = azurerm_mssql_server.tp_sql_server.fully_qualified_domain_name
}

output "azure_sql_database_name" {
  description = "Azure SQL Database name"
  value       = azurerm_mssql_database.tp_database.name
}