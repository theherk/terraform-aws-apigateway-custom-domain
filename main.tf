locals {
  apigateway_domains = var.skip_apigateway_domains ? [] : toset(concat(try([coalesce(var.domain_name)], []), var.domain_names_alternate))
}

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

  id = var.vpc_endpoint_api.id
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
  # This looks crazy because of the unknown until apply-time issue.
  # But since sets of strings are sorted lexicographically, this should be
  # stable.
  for_each = ({ for i, v in range(length(var.subnet_ids)) : i =>
    var.vpc_endpoint_api == null
    ? tolist(aws_vpc_endpoint.api[0].network_interface_ids)[i]
    : tolist(data.aws_vpc_endpoint.api[0].network_interface_ids)[i]
  })

  id = each.value
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = data.aws_network_interface.this

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = each.value.private_ip
  port             = 443
}

resource "aws_vpc_endpoint_service" "this" {
  # checkov:skip=CKV_AWS_123: Prefer no acceptance.
  count = var.vpc_endpoint_remote != null || var.vpc_endpoint_local ? 1 : 0

  acceptance_required        = false
  allowed_principals         = var.allowed_principals
  network_load_balancer_arns = [aws_lb.this.arn]
  tags                       = { Name = var.name }
}

resource "aws_vpc_endpoint" "local" {
  count = var.vpc_endpoint_remote == null && var.vpc_endpoint_local ? 1 : 0

  security_group_ids = [aws_security_group.api_endpoint[0].id]
  service_name       = aws_vpc_endpoint_service.this[0].service_name
  subnet_ids         = var.subnet_ids
  tags               = { Name = var.name }
  vpc_endpoint_type  = "Interface"
  vpc_id             = var.vpc_id
}

resource "aws_route53_record" "this" {
  zone_id        = var.zone_id
  name           = var.domain_name
  set_identifier = try(var.routing_policy.set_identifier, null)
  type           = "A"

  alias {
    name                   = coalesce(var.vpc_endpoint_remote, try(aws_vpc_endpoint.local[0].dns_entry[0].dns_name, null), aws_lb.this.dns_name)
    zone_id                = var.vpc_endpoint_remote != null || var.vpc_endpoint_local ? local.vpc_region_zone_id[data.aws_region.current.name] : aws_lb.this.zone_id
    evaluate_target_health = true
  }

  dynamic "cidr_routing_policy" {
    for_each = var.routing_policy != null ? var.routing_policy.cidr != null ? [var.routing_policy.cidr] : [] : []

    content {
      collection_id = cidr_routing_policy.value.collection_id
      location_name = cidr_routing_policy.value.location_name
    }
  }

  dynamic "failover_routing_policy" {
    for_each = var.routing_policy != null ? var.routing_policy.failover != null ? [var.routing_policy.failover] : [] : []

    content {
      type = failover_routing_policy.value.type
    }
  }

  dynamic "geolocation_routing_policy" {
    for_each = var.routing_policy != null ? var.routing_policy.geolocation != null ? [var.routing_policy.geolocation] : [] : []

    content {
      continent   = geolocation_routing_policy.value.continent
      country     = geolocation_routing_policy.value.country
      subdivision = geolocation_routing_policy.value.subdivision
    }
  }

  dynamic "geoproximity_routing_policy" {
    for_each = var.routing_policy != null ? var.routing_policy.geoproximity != null ? [var.routing_policy.geoproximity] : [] : []

    content {
      aws_region       = geoproximity_routing_policy.value.aws_region
      bias             = geoproximity_routing_policy.value.bias
      local_zone_group = geoproximity_routing_policy.value.local_zone_group

      dynamic "coordinates" {
        for_each = geoproximity_routing_policy.value != null ? geoproximity_routing_policy.value.coordinates != null ? [geoproximity_routing_policy.value.coordinates] : [] : []

        content {
          latitude  = coordinates.value.latitude
          longitude = coordinates.value.longitude
        }
      }
    }
  }

  dynamic "latency_routing_policy" {
    for_each = var.routing_policy != null ? var.routing_policy.latency != null ? [var.routing_policy.latency] : [] : []

    content {
      region = latency_routing_policy.value.region
    }
  }

  dynamic "weighted_routing_policy" {
    for_each = var.routing_policy != null ? var.routing_policy.weighted != null ? [var.routing_policy.weighted] : [] : []

    content {
      weight = weighted_routing_policy.value.weight
    }
  }
}

resource "aws_api_gateway_domain_name" "this" {
  for_each = local.apigateway_domains

  domain_name              = each.key
  regional_certificate_arn = var.certificate_arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_base_path_mapping" "this" {
  for_each = local.apigateway_domains

  api_id      = var.api_id
  stage_name  = var.api_stage
  domain_name = aws_api_gateway_domain_name.this[each.key].domain_name
}
