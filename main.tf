terraform {
  required_providers {
    snowflake = {
      source = "Snowflake-Labs/snowflake"
      version = "1.0.3"
    }
  }
}

# A simple configuration of the provider with a default authentication.
# A default value for `authenticator` is `snowflake`, enabling authentication with `user` and `password`.
provider "snowflake" {
  organization_name = var.SNOWFLAKE_ORGANIZATION_NAME # required if not using profile. Can also be set via SNOWFLAKE_ORGANIZATION_NAME env var
  account_name      = var.SNOWFLAKE_ACCOUNT_NAME # required if not using profile. Can also be set via SNOWFLAKE_ACCOUNT_NAME env var
  user              = var.SNOWFLAKE_USER_NAME # required if not using profile or token. Can also be set via SNOWFLAKE_USER env var
  password          = var.SNOWFLAKE_PASSWORD
  
}

resource "snowflake_warehouse" "wh" {
  for_each = toset(var.warehouse_names)
  name     = "${var.ENV}_WH_${each.key}_${var.NAME}"
  comment  = "Warehouse for ${each.key}"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
  auto_resume    = true
}

resource "snowflake_database" "demo_db" {
  name    = "${var.ENV}_DB_${var.NAME}"
  comment = "Database for Snowflake Terraform demo"
}
resource "snowflake_schema" "schemas" {
  for_each = toset(var.schema_names)
  
  database = snowflake_database.demo_db.name
  name     = each.key
}

# Create Snowflake Role
resource "snowflake_account_role" "snowflake_dbaccount_admin_role" {
  name     = var.dbaccount_admin_role
  comment  = ""
}
# Grant New Role to SYSADMIN
resource "snowflake_grant_account_role" "snowflake_role_sysadmin_grant" {
  role_name        = snowflake_account_role.snowflake_dbaccount_admin_role.name
  parent_role_name = "SYSADMIN"

  depends_on = [
    snowflake_account_role.snowflake_dbaccount_admin_role
  ]
}

resource "snowflake_grant_ownership" "ownership_to_acc_role" {
  for_each = snowflake_warehouse.wh
  account_role_name = snowflake_account_role.snowflake_dbaccount_admin_role.name
  on {
    object_type = "WAREHOUSE"
    object_name = each.value.name
  }
}
resource "snowflake_grant_ownership" "test" {
  account_role_name = snowflake_account_role.snowflake_dbaccount_admin_role.name
  on {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}
resource "snowflake_account_role" "create_schema_role" {
  name     = "${var.ENV}_AR_CS_${var.NAME}"
  comment  = "CREATE SCHEMA ROLE"
}
#Grant Usage on Databases to DBT Role
resource "snowflake_grant_privileges_to_account_role" "dbt_role_raw_database_usage_grant" {
  privileges        = ["CREATE SCHEMA"]
  account_role_name = snowflake_account_role.create_schema_role.name
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
 }
resource "snowflake_account_role" "schema_roles_rw" {
  for_each = toset(var.schema_names)
  
  name    = "${var.ENV}_AR_${each.value}_RW_${var.NAME}"
  comment = "Read-Write role for ${each.value} schema"
}
resource "snowflake_account_role" "schema_roles_ro" {
  for_each = toset(var.schema_names)
  
  name    = "${var.ENV}_AR_${each.value}_RO_${var.NAME}"
  comment = "Read-only role for ${each.value} schema"
}

resource "snowflake_account_role" "warehouse_roles" {
  for_each = toset(var.warehouse_names)

  name    = "${var.ENV}_WR_${each.value}_${var.NAME}"
  comment = "Role for ${each.value} Warehouse"
}
resource "snowflake_grant_privileges_to_account_role" "wh_usage" {
  for_each = toset(var.warehouse_names)
  
  privileges         = ["USAGE"]
  account_role_name  = snowflake_account_role.warehouse_roles[each.value].name
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.wh[each.value].name
  }
}
resource "snowflake_account_role" "fr_roles" {
  for_each = toset(var.fr_roles)

  name    = "${var.ENV}_FR_${each.value}_${var.NAME}"
  comment = "Frontend role for ${each.value}"
}
resource "snowflake_grant_account_role" "fr_inheritance" {
  for_each = toset(var.fr_roles)

  role_name   = snowflake_account_role.fr_roles[each.value].name
  parent_role_name = "${var.ENV}_WR_${each.value}_${var.NAME}"
}
resource "snowflake_account_role" "task_operator" {
  name    = "TASK_OPERATOR"
  comment = "Role responsible for running tasks"
}
resource "snowflake_grant_account_role" "fr_roles_to_existing_user" {
  for_each = toset(var.fr_roles)

  role_name = "${var.ENV}_FR_${each.value}_${var.NAME}"
  user_name = var.SNOWFLAKE_USER_NAME
}

resource "snowflake_grant_account_role" "task_operator_inherits" {
  for_each          = { for role in var.task_operator_parents : role => "${var.ENV}_${role}_${var.NAME}" }
  role_name         = snowflake_account_role.task_operator.name
  parent_role_name   = each.value
}
# Grant USAGE on Database to RW Roles
resource "snowflake_grant_privileges_to_account_role" "db_usage_rw" {
  for_each = snowflake_account_role.schema_roles_rw
  
  privileges        = ["USAGE"]
  account_role_name = each.value.name
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}

# Grant USAGE on Database to RO Roles
resource "snowflake_grant_privileges_to_account_role" "db_usage_ro" {
  for_each = snowflake_account_role.schema_roles_ro
  
  privileges        = ["USAGE"]
  account_role_name = each.value.name
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}

# Grant ALL PRIVILEGES to RW roles on respective schemas

resource "snowflake_grant_privileges_to_account_role" "rw_privileges" {
  for_each = snowflake_schema.schemas

  privileges        = ["ALL PRIVILEGES"]
  account_role_name = snowflake_account_role.schema_roles_rw[each.key].name
  on_schema {
    schema_name = each.value.fully_qualified_name
  }
}
# Grant USAGE to RO roles on respective schemas
resource "snowflake_grant_privileges_to_account_role" "ro_usage" {
  for_each = snowflake_schema.schemas
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.schema_roles_ro[each.key].name
  on_schema {
    schema_name = each.value.fully_qualified_name
  }
}
# Grant SELECT on all existing tables in each schema to corresponding RO role
resource "snowflake_grant_privileges_to_account_role" "ro_select_existing" {
  for_each = snowflake_schema.schemas
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.schema_roles_ro[each.key].name
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = each.value.fully_qualified_name
    }
  }
}

# Grant SELECT on all future tables in each schema to corresponding RO role
resource "snowflake_grant_privileges_to_account_role" "ro_select_future" {
  for_each = snowflake_schema.schemas
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.schema_roles_ro[each.key].name

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = each.value.fully_qualified_name
    }
  }
}
resource "snowflake_grant_account_role" "fr_inheritance_rw_roles" {
  for_each = toset(keys(snowflake_account_role.schema_roles_rw))

  role_name        = snowflake_account_role.fr_roles["ENGR"].name
  parent_role_name = "${var.ENV}_AR_${each.value}_RW_${var.NAME}"
}
resource "snowflake_grant_account_role" "fr_inheritance_ro_roles" {
  for_each = toset(keys(snowflake_account_role.schema_roles_ro))

  role_name        = snowflake_account_role.fr_roles["RDR"].name
  parent_role_name = "${var.ENV}_AR_${each.value}_RO_${var.NAME}"
}
resource "snowflake_grant_account_role" "ar_cs_inherit_to_fr_engr" {
   
  role_name        = snowflake_account_role.fr_roles["ENGR"].name
  parent_role_name = "${var.ENV}_AR_CS_${var.NAME}"
}
resource "snowflake_grant_account_role" "fr_roles_inherit_to_tsysadmin" {
  for_each = snowflake_account_role.fr_roles
  role_name        = snowflake_account_role.snowflake_service_role.name
  parent_role_name = each.value.name
}
