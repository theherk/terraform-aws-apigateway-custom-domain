output "vpc_endpoint_service" {
  description = "VPC Endpoint Service toward load balancer. This can be used to generate a VPC Endpoint Interface in another connectivity account."
  value       = try(aws_vpc_endpoint_service.this[0])
}
