# ─────────────────────────────────────────────────────────────────────────────
# NZ Labour Market Intelligence — Snowflake infrastructure
#
# Codifies what snowflake/01_setup_roles_and_databases.sql creates manually:
# one warehouse, one database, five schemas, and a three-role hierarchy with
# matching grants. See terraform/README.md for how this relates to the SQL
# scripts.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.89"
    }
  }
}

provider "snowflake" {
  account  = var.snowflake_account
  user     = var.snowflake_user
  password = var.snowflake_password
  role     = var.snowflake_role
}

# ── Warehouse ──────────────────────────────────────────────────────────────
resource "snowflake_warehouse" "nz_labour_wh" {
  name                = "NZ_LABOUR_WH"
  warehouse_size      = var.warehouse_size
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "NZ Labour Intelligence Platform — compute warehouse"
}

# ── Database ───────────────────────────────────────────────────────────────
resource "snowflake_database" "nz_labour_db" {
  name    = "NZ_LABOUR_DB"
  comment = "NZ Labour Market Intelligence — production"
}

# ── Schemas ────────────────────────────────────────────────────────────────
resource "snowflake_schema" "raw" {
  database = snowflake_database.nz_labour_db.name
  name     = "RAW"
  comment  = "Raw ingested data from Stats NZ"
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.nz_labour_db.name
  name     = "STAGING"
  comment  = "dbt staging layer — cleaned source data"
}

resource "snowflake_schema" "intermediate" {
  database = snowflake_database.nz_labour_db.name
  name     = "INTERMEDIATE"
  comment  = "dbt intermediate layer — business logic"
}

resource "snowflake_schema" "mart" {
  database = snowflake_database.nz_labour_db.name
  name     = "MART"
  comment  = "dbt mart layer — final models for reporting"
}

resource "snowflake_schema" "audit" {
  database = snowflake_database.nz_labour_db.name
  name     = "AUDIT"
  comment  = "Pipeline audit logs and test results"
}

# ── Role hierarchy ─────────────────────────────────────────────────────────
#
#  ACCOUNTADMIN
#       │
#  SYSADMIN
#       │
#  ENGINEER_ROLE  ← full read/write on all schemas
#       │
#  ANALYST_ROLE   ← read on STAGING, INTERMEDIATE, MART
#       │
#  REPORTER_ROLE  ← read on MART only

resource "snowflake_role" "engineer" {
  name    = "ENGINEER_ROLE"
  comment = "Data engineers — full pipeline access"
}

resource "snowflake_role" "analyst" {
  name    = "ANALYST_ROLE"
  comment = "Data analysts — read transformed data"
}

resource "snowflake_role" "reporter" {
  name    = "REPORTER_ROLE"
  comment = "Power BI / report consumers — mart only"
}

resource "snowflake_grant_account_role" "engineer_to_sysadmin" {
  role_name        = snowflake_role.engineer.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "analyst_to_engineer" {
  role_name        = snowflake_role.analyst.name
  parent_role_name = snowflake_role.engineer.name
}

resource "snowflake_grant_account_role" "reporter_to_analyst" {
  role_name        = snowflake_role.reporter.name
  parent_role_name = snowflake_role.analyst.name
}

# ── Warehouse usage grants ─────────────────────────────────────────────────
resource "snowflake_grant_privileges_to_account_role" "warehouse_usage" {
  for_each = toset([
    snowflake_role.engineer.name,
    snowflake_role.analyst.name,
    snowflake_role.reporter.name,
  ])

  account_role_name = each.value
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.nz_labour_wh.name
  }
}

# ── Database usage grants ──────────────────────────────────────────────────
resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  for_each = toset([
    snowflake_role.engineer.name,
    snowflake_role.analyst.name,
    snowflake_role.reporter.name,
  ])

  account_role_name = each.value
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.nz_labour_db.name
  }
}

# ── Schema grants — Engineer: full access to all schemas ──────────────────
resource "snowflake_grant_privileges_to_account_role" "engineer_raw" {
  account_role_name = snowflake_role.engineer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE STAGE", "CREATE PIPE"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.raw.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_staging" {
  account_role_name = snowflake_role.engineer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.staging.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_intermediate" {
  account_role_name = snowflake_role.engineer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.intermediate.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_mart" {
  account_role_name = snowflake_role.engineer.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.mart.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_audit" {
  account_role_name = snowflake_role.engineer.name
  privileges        = ["USAGE", "CREATE TABLE"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.audit.name}\""
  }
}

# ── Schema grants — Analyst: read on transformed schemas only ─────────────
resource "snowflake_grant_privileges_to_account_role" "analyst_staging" {
  account_role_name = snowflake_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.staging.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_intermediate" {
  account_role_name = snowflake_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.intermediate.name}\""
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_mart" {
  account_role_name = snowflake_role.analyst.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.mart.name}\""
  }
}

# ── Schema grants — Reporter: mart only ────────────────────────────────────
resource "snowflake_grant_privileges_to_account_role" "reporter_mart" {
  account_role_name = snowflake_role.reporter.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "\"${snowflake_database.nz_labour_db.name}\".\"${snowflake_schema.mart.name}\""
  }
}
