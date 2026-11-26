variable "prefix" {
  type    = string
  default = "bmdemo-mk8s"
}

variable "region" {
  type    = string
  default = "europe-west6"
}

variable "mlb_cidr" {
  type        = string
  default     = "10.100.0.0/16"
  description = "CIDR range for metallb"
}

variable "node_cidr" {
  type    = string
  default = "10.0.0.0/24"
}
variable "admin_username" {
  type = string
}

variable "node_count" {
  type    = number
  default = 1
}
