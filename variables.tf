variable "allowed_principals" {
  description = "Principals allowed to discover the VPC Endpoint Service. By default, principals outside the VPC will not be able to create interfaces to the Endpoint Service."
  type        = list(string)
  default     = null
}

variable "api_id" {
  description = "API to which the requests are destined."
  type        = string
}

variable "api_stage" {
  description = "Name of the stage used for the base path mapping."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate to attach to the listener."
  type        = string
}

variable "domain_name" {
  description = "Domain name to access api. This will point to the remote VPC Endpoint if `remote_vpc_endpoint` is given, or to a generated VPC Endpoint otherwise."
  type        = string
}

variable "domain_names_alternate" {
  description = "Alternate domain names to access the api. These alternate names are for subject alternative names in the given certificate."
  type        = list(string)
  default     = []
}

variable "lb_enable_deletion_protection" {
  description = "Boolean indicating if deletion protection should be enabled for the created load balancer. If `lb` is given, this is ignored."
  type        = bool
  default     = null
}

variable "lb_log_bucket" {
  description = "S3 bucket into which the created load balancer will store access logs. If `lb` is given, this is ignored. Even if `lb` is not given, this is not required."
  type        = string
  default     = null
}

variable "name" {
  description = "A name used to identify associated resources throughout, like endpoints and load balancer."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the target group."
  type        = list(string)
}

variable "vpc_endpoint_api" {
  description = "VPC Endpoint for execute-api. If not given, one will be created."
  type        = string
  default     = null
}

variable "vpc_endpoint_local" {
  description = "Boolean indicating is a VPC Endpoint Interface should be created in the account with the API. If `false` and no `vpc_endpoint_remote` given, the DNS record will point directly to the NLB. This will be slightly less expensive, but it works. However, if you have any intention of using an IP allow list to allow traffic through a firewall, this may not be a good option since the IP addresses of NLB's can change unexpectedly. Ignored if `vpc_endpoint_remote` given."
  type        = bool
  default     = false
}

variable "vpc_endpoint_remote" {
  description = "VPC Endpoint in another connectivity account for calling the VPC Endpoint Service created in the API's account. If not provided, a second VPC Endpoint will be created in the API's account to point toward the VPC Endpoint Service which reaches the NLB. When added, the endpoint created in this account to reach the service will be removed."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "ID of the VPC."
  type        = string
}

variable "zone_id" {
  description = "Zone into which the custom domain should be added."
  type        = string
}
