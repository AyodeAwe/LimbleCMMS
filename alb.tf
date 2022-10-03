locals {
  target_groups = [
    "green",
    "blue"
  ]
  is_private_alb = tobool(var.is_private_alb)
}

resource "aws_lb" "main" {
  internal           = local.is_private_alb
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.is_private_alb ? data.terraform_remote_state.networking.outputs.subnets_private : data.terraform_remote_state.networking.outputs.subnets_public

  tags = {
    Name        = "${service_name}-alb"
    Terraform   = true
  }
}

resource "aws_lb_target_group" "main" {
  count       = length(local.target_groups)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  health_check {
    interval = 30
    path     = "/health"
    port     = var.container_port
  }

  tags = {
    Name        = "${service_name}-${element(local.target_groups, count.index)}"
    Environment = local.workspace
    Terraform   = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = resource.aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.*.arn[0]
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name       = var.hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_lb_listener_rule" "https" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 90

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.*.arn[0]
  }

  condition {
    host_header {
      values = var.hostname
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener" "https_test" {
  load_balancer_arn = resource.aws_lb.main.arn
  port              = "6443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.cert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.*.arn[0]
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

resource "aws_lb_listener_rule" "https_test" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.*.arn[0]
  }

  condition {
    host_header {
      values = var.hostname
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = resource.aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_route53_zone" "primary" {
  name = "abc.com"
}

resource "aws_route53_record" "elb" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.hostname
  type    = "A"

  alias {
    name                   = resource.aws_lb.main.dns_name
    zone_id                = resource.aws_lb.main.zone_id
    evaluate_target_health = false
  }
}
