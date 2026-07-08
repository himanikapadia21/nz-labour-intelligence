output "warehouse_name" {
  description = "Name of the provisioned virtual warehouse."
  value       = snowflake_warehouse.nz_labour_wh.name
}

output "database_name" {
  description = "Name of the provisioned database."
  value       = snowflake_database.nz_labour_db.name
}

output "role_names" {
  description = "Names of the provisioned account roles, in hierarchy order."
  value = [
    snowflake_role.engineer.name,
    snowflake_role.analyst.name,
    snowflake_role.reporter.name,
  ]
}
