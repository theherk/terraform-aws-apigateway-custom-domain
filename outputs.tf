output "vpc_endpoint_service" {
  description = "VPC Endpoint Service toward load balancer is `var.vpc_endpoint_service = true`."
  value       = aws_vpc_endpoint_service.this
}
