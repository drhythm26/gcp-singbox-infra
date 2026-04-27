variable "project_id" {
  type = string
}

variable "hk_region" {
  type    = string
  default = "asia-east2"
}

variable "sg_region" {
  type    = string
  default = "asia-southeast1"
}

variable "hk_zone" {
  type    = string
  default = "asia-east2-a"
}

variable "sg_zone" {
  type    = string
  default = "asia-southeast1-a"
}

variable "image_project" {
  type    = string
  default = "ubuntu-os-cloud"
}

variable "image_family" {
  type    = string
  default = "ubuntu-2404-lts-amd64"
}

variable "ssh_user" {
  type    = string
  default = "lan"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/google_compute_engine.pub"
}

variable "admin_cidr" {
  type = list(string)
}