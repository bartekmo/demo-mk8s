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

variable "dns_root" {
  type        = string
  description = "Root DNS domain; Argo CD is exposed at argocd.<dns_root>"
}

variable "acme_email" {
  type        = string
  description = "Contact email for the Let's Encrypt account"
}

variable "gitops_repo_url" {
  type        = string
  default     = "https://github.com/bartekmo/demo-mk8s.git"
  description = "Git repo the Argo CD root Application syncs from"
}

variable "gitops_repo_path" {
  type        = string
  default     = "k8s-apps"
  description = "Directory in the repo synced (recursively) by the root Application"
}

variable "gitops_repo_revision" {
  type    = string
  default = "main"
}

variable "argocd_version" {
  type        = string
  default     = "stable"
  description = "Argo CD git ref (tag/branch) for the upstream install manifest"
}

variable "boot_disk_gb" {
  type        = number
  default     = 50
  description = "Node boot disk size (holds container images and microk8s data)"
}

variable "boot_disk_type" {
  type    = string
  default = "pd-balanced"
}

variable "lw_account" {
  type        = string
  description = "FortiCNAPP account name"
  nullable    = true
  default     = null
}

variable "lw_api_key" {
  type        = string
  description = "FortiCNAPP API key"
  nullable    = true
  default     = null
  sensitive   = true
}

variable "lw_api_secret" {
  type        = string
  description = "FortiCNAPP API secret"
  nullable    = true
  default     = null
  sensitive   = true
}

variable "lw_subaccount" {
  type        = string
  description = "FortiCNAPP subaccount name"
  nullable    = true
  default     = null
}
