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

resource "snowflake_schema" "src_stg" {
  database = snowflake_database.demo_db.name
  name     = "STG"
}

resource "snowflake_schema" "mdl" {
  database = snowflake_database.demo_db.name
  name     = "MDL"
}

resource "snowflake_schema" "dwh" {
  database = snowflake_database.demo_db.name
  name     = "DWH"
}

# Create Snowflake Role
resource "snowflake_account_role" "snowflake_service_role" {
  name     = "TZSYSADMIN_DEV"
  comment  = ""
}
# Grant New Role to SYSADMIN
resource "snowflake_grant_account_role" "snowflake_role_sysadmin_grant" {
  role_name        = "TZSYSADMIN_DEV"
  parent_role_name = "SYSADMIN"

  depends_on = [
    snowflake_account_role.snowflake_service_role
  ]
}

resource "snowflake_grant_ownership" "ownership_to_acc_role" {
  for_each = snowflake_warehouse.wh
  account_role_name = "TZSYSADMIN_DEV"
  on {
    object_type = "WAREHOUSE"
    object_name = each.value.name
  }
}
resource "snowflake_grant_ownership" "test" {
  account_role_name = snowflake_account_role.snowflake_service_role.name
  on {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}
resource "snowflake_account_role" "create_schema_role" {
  name     = "AR_CS"
  comment  = "CREATE SCHEMA ROLE"
}
# Grant Usage on Databases to DBT Role
resource "snowflake_grant_privileges_to_account_role" "dbt_role_raw_database_usage_grant" {
  privileges        = ["CREATE SCHEMA"]
  account_role_name = "AR_CS"
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}

resource "snowflake_account_role" "ar_src_rw_role" {
  name     = "AR_SRC_RW"
  comment  = "RW role"
}
resource "snowflake_account_role" "ar_mdl_rw_role" {
  name     = "AR_MDL_RW"
  comment  = "RW role"
}
resource "snowflake_account_role" "ar_dwh_rw_role" {
  name     = "AR_DWH_RW"
  comment  = "RW role"
}
resource "snowflake_account_role" "ar_src_ro_role" {
  name     = "AR_SRC_RO"
  comment  = "RO role"
}
resource "snowflake_account_role" "ar_mdl_ro_role" {
  name     = "AR_MDL_RO"
  comment  = "RO role"
}
resource "snowflake_account_role" "ar_dwh_ro_role" {
  name     = "AR_DWH_RO"
  comment  = "RO role"
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

resource "snowflake_grant_privileges_to_account_role" "db_usage_all" {
  for_each = {
    ar_src_rw = snowflake_account_role.ar_src_rw_role.name
    ar_src_ro = snowflake_account_role.ar_src_ro_role.name
    ar_mdl_rw = snowflake_account_role.ar_mdl_rw_role.name
    ar_mdl_ro = snowflake_account_role.ar_mdl_ro_role.name
    ar_dwh_rw = snowflake_account_role.ar_dwh_rw_role.name
    ar_dwh_ro = snowflake_account_role.ar_dwh_ro_role.name
  }

  privileges        = ["USAGE"]
  account_role_name = each.value
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.demo_db.name
  }
}

# Grant ALL PRIVILEGES to RW roles on respective schemas
resource "snowflake_grant_privileges_to_account_role" "src_rw_priv" {
  privileges        = ["ALL PRIVILEGES"]
  account_role_name = snowflake_account_role.ar_src_rw_role.name
  on_schema {
    schema_name = snowflake_schema.src_stg.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "mdl_rw_priv" {
  privileges        = ["ALL PRIVILEGES"]
  account_role_name = snowflake_account_role.ar_mdl_rw_role.name
  on_schema {
    schema_name = snowflake_schema.mdl.fully_qualified_name
  }
}
resource "snowflake_grant_privileges_to_account_role" "dwh_rw_priv" {
  privileges        = ["ALL PRIVILEGES"]
  account_role_name = snowflake_account_role.ar_dwh_rw_role.name
  on_schema {
    schema_name = snowflake_schema.dwh.fully_qualified_name
  }
}


# Grant USAGE and SELECT to RO roles on respective schemas
resource "snowflake_grant_privileges_to_account_role" "src_ro_priv" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.ar_src_ro_role.name
  on_schema {
    schema_name = snowflake_schema.src_stg.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "mdl_ro_priv" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.ar_mdl_ro_role.name
  on_schema {
    schema_name = snowflake_schema.mdl.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "dwh_ro_priv" {
  privileges        = ["USAGE"]
  account_role_name = snowflake_account_role.ar_dwh_ro_role.name
  on_schema {
    schema_name = snowflake_schema.dwh.fully_qualified_name
  }
}
# Grant SELECT and INSERT on all tables in SRC schema to RO role
resource "snowflake_grant_privileges_to_account_role" "src_ro_select" {
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.ar_src_ro_role.name
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.src_stg.fully_qualified_name
    }
  }
  depends_on = [snowflake_schema.src_stg, snowflake_account_role.ar_src_ro_role]

}
# Grant SELECT and INSERT on all tables in MDL schema to RO role
resource "snowflake_grant_privileges_to_account_role" "mdl_ro_select" {
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.ar_mdl_ro_role.name
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.mdl.fully_qualified_name
    }
  }
}

# Grant SELECT and INSERT on all tables in DWH schema to RO role
resource "snowflake_grant_privileges_to_account_role" "dwh_ro_select" {
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.ar_dwh_ro_role.name
  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.dwh.fully_qualified_name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "src_ro_future_select" {
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.ar_src_ro_role.name

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.src_stg.fully_qualified_name
    }
  }
}
resource "snowflake_grant_privileges_to_account_role" "mdl_ro_future_priv" {
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.ar_mdl_ro_role.name

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.mdl.fully_qualified_name
    }
  }
}
resource "snowflake_grant_privileges_to_account_role" "dwh_ro_future_priv" {
  privileges        = ["SELECT"]
  account_role_name = snowflake_account_role.ar_dwh_ro_role.name

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.dwh.fully_qualified_name
    }
  }
}
