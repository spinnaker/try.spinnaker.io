variable "region" {
  default = "us-east-2"
}

variable "route53_zone" {
  default = "gsoc.armory.io"
}

variable "domain_name" {
  default = "try.gsoc.armory.io"
}

variable "namespace" {
  default = "spinnaker"
}

variable "public_facing" {
  default = true
}