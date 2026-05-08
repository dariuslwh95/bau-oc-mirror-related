variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "mount_path" {
  type    = string
  default = "/mnt/mirror-data"
}