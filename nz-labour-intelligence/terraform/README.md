# Terraform — Snowflake Infrastructure

This codifies the same Snowflake objects that
[`snowflake/01_setup_roles_and_databases.sql`](../snowflake/01_setup_roles_and_databases.sql)
creates manually: the `NZ_LABOUR_WH` warehouse, the `NZ_LABOUR_DB` database,
its five schemas (`RAW`, `STAGING`, `INTERMEDIATE`, `MART`, `AUDIT`), the
three-role hierarchy (`ENGINEER_ROLE` → `ANALYST_ROLE` → `REPORTER_ROLE`), and
the grants between them.

The SQL script is the documented "what" (run once, by hand, on
`ACCOUNTADMIN`, and easy to read top to bottom). This Terraform config is the
reproducible "how" — going forward it is the source of truth for
provisioning these objects. Both are kept: the SQL script is not deleted.

Not yet covered by Terraform (still handled by the SQL scripts):
[`02_create_staging_tables.sql`](../snowflake/02_create_staging_tables.sql)
(RAW tables + audit log) and
[`03_rbac_and_security.sql`](../snowflake/03_rbac_and_security.sql) (masking
policy, row access policy, resource monitor), plus the
`NZ_LABOUR_PIPELINE_USER` service user. These involve either dbt-managed
table DDL or a password better kept out of Terraform state for now — good
candidates for a later iteration.

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in real credentials, never commit this file
terraform init
terraform plan
terraform apply
```

## ⚠️ Before you run this against a real account

If `NZ_LABOUR_WH`, `NZ_LABOUR_DB`, or the three roles already exist (they do,
if you've run the SQL scripts before), running `terraform apply` directly
will fail with duplicate-object errors — Terraform doesn't know about them
yet. Bring them under management first with `terraform import`, e.g.:

```bash
terraform import snowflake_warehouse.nz_labour_wh NZ_LABOUR_WH
terraform import snowflake_database.nz_labour_db NZ_LABOUR_DB
terraform import snowflake_role.engineer ENGINEER_ROLE
# ...and so on for each resource in main.tf
```

Only run `apply` after importing, and review the resulting `terraform plan`
carefully — this is real infrastructure, not a fresh account.

## Notes on the provider

- Pinned to `Snowflake-Labs/snowflake ~> 0.89`, which is where `snowflake_role`
  (rather than the newer `snowflake_account_role`) and
  `snowflake_grant_privileges_to_account_role` coexist. `terraform validate`
  currently resolves this to the newest matching 0.x release, which prints a
  deprecation warning on `snowflake_role` (it's being replaced by
  `snowflake_account_role`) — non-fatal, but worth migrating eventually.
- The registry also warns that `Snowflake-Labs/snowflake` has moved to
  `snowflakedb/snowflake`. It still resolves today; if that changes, update
  the `source` in `main.tf`.
- No `.terraform.lock.hcl` is committed — it's platform-specific (this repo
  develops on Windows, CI runs on Linux), so each environment generates its
  own on `terraform init` rather than sharing a lock file that would only
  have hashes for one platform.
