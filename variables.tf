variable "SNOWFLAKE_ORGANIZATION_NAME" {
    type = string
    default = "SVQKFBE"
}
variable "SNOWFLAKE_ACCOUNT_NAME" {
    type = string
    default = "LK10506"
}
variable "SNOWFLAKE_USER_NAME" {
    type = string
    default = "PREETIMITRA1"
}
variable "SNOWFLAKE_PASSWORD" {
    type = string
    default = "Preetimitra1@2024"
}
variable "ENV" {
    type = string
    default = "DEV"
}
variable "NAME" {
    type = string
    default = "APPLICATION_NAME"
}
variable "warehouse_names" {
  description = "List of warehouse names to be created"
  type        = list(string)
  default     = ["TO", "ENGR", "RDR"]
}
variable "schema_names" {
  description = "List of schema names to be created"
  type        = list(string)
  default     = ["STG", "MDL", "DWH"]
}
variable "fr_roles" {
  description = "List of FR roles to be created"
  type = list(string)
  default = ["RDR", "ENGR"]
}
variable "task_operator_parents" {
  description = "List of roles to be inherited by Task Operator"
  type        = list(string)
  default     = ["WR_TO", "FR_ENGR"]
}
variable "dbaccount_admin_role" {
  description = "snowflake dbaccount admin role"
  type        = string
  default     = "TZSYSADMIN_DEV"
}