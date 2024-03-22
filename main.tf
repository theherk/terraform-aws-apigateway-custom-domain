data "aws_region" "current" {}

data "aws_subnet" "this" {
  for_each = toset(var.subnet_ids)
  id       = each.value
}

resource "aws_security_group" "api_endpoint" {
  count = var.vpc_endpoint_api == null || var.vpc_endpoint_remote == null ? 1 : 0

  description = "Security group for ${var.name} vpc endpoints."
  name        = var.name
  tags        = { Name = var.name }
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = [for s in data.aws_subnet.this : s.cidr_block]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = [for s in data.aws_subnet.this : s.cidr_block]
  }
}

data "aws_vpc_endpoint" "api" {
  count = var.vpc_endpoint_api != null ? 1 : 0

  id = var.vpc_endpoint_api
}

resource "aws_vpc_endpoint" "api" {
  count = var.vpc_endpoint_api == null ? 1 : 0

  private_dns_enabled = true
  security_group_ids  = [aws_security_group.api_endpoint[0].id]
  service_name        = "com.amazonaws.${data.aws_region.current.name}.execute-api"
  subnet_ids          = var.subnet_ids
  tags                = { Name = var.name }
  vpc_endpoint_type   = "Interface"
  vpc_id              = var.vpc_id
}

resource "aws_lb" "this" {
  name                             = var.name
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.lb_enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.lb_log_bucket != null ? [1] : []

    content {
      bucket  = var.lb_log_bucket
      enabled = true
    }
  }
}

resource "aws_lb_listener" "this" {
  certificate_arn   = var.certificate_arn
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "TLS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_target_group" "this" {
  name        = var.name
  port        = 443
  protocol    = "TLS"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
  }
}

data "aws_network_interface" "this" {
  for_each = var.vpc_endpoint_api == null ? aws_vpc_endpoint.api[0].network_interface_ids : data.aws_vpc_endpoint.api[0].network_interface_ids

  id = each.key
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = data.aws_network_interface.this

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = each.value.private_ip
  port             = 443
}

resource "aws_vpc_endpoint_service" "this" {
  # checkov:skip=CKV_AWS_123: Prefer no acceptance.
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.this.arn]
  tags                       = { Name = var.name }
}

resource "aws_vpc_endpoint" "local" {
  count = var.vpc_endpoint_remote == null ? 1 : 0

  security_group_ids = [aws_security_group.api_endpoint[0].id]
  service_name       = aws_vpc_endpoint_service.this.service_name
  subnet_ids         = var.subnet_ids
  tags               = { Name = var.name }
  vpc_endpoint_type  = "Interface"
  vpc_id             = var.vpc_id
}

resource "aws_route53_record" "this" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = coalesce(var.vpc_endpoint_remote, aws_vpc_endpoint.local[0].dns_entry[0].dns_name)
    zone_id                = local.vpc_region_zone_id[data.aws_region.current.name]
    evaluate_target_health = true
  }
}

resource "aws_api_gateway_domain_name" "this" {
  for_each = toset(concat(try([coalesce(var.domain_name)], []), var.domain_names_alternate))

  domain_name              = each.key
  regional_certificate_arn = var.certificate_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "this" {
  for_each = toset(concat(try([coalesce(var.domain_name)], []), var.domain_names_alternate))

  api_id      = var.api_id
  stage_name  = var.api_stage
  domain_name = aws_api_gateway_domain_name.this[each.key].domain_name
}
