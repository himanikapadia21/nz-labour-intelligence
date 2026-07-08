variable "snowflake_account" {
  description = "Snowflake account identifier (e.g. xy12345.ap-southeast-2)."
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake user Terraform authenticates as (needs ACCOUNTADMIN, matching the SQL setup script)."
  type        = string
}

variable "snowflake_password" {
  description = "Password for snowflake_user."
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Role Terraform assumes when connecting."
  type        = string
  default     = "ACCOUNTADMIN"
}

variable "warehouse_size" {
  description = "Size of NZ_LABOUR_WH."
  type        = string
  default     = "X-SMALL"
}
