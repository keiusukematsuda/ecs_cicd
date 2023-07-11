#####################################################################################################################################################################
###
### Summary : ALB
###
#####################################################################################################################################################################
# - Resource
#   - main
#     - LoadBalancer
#     - Target Group
#     - Listenr
#   - sub 
#     - Security Group

#####################################################################################################################################################################
###
### Parameter
###
#####################################################################################################################################################################

locals {
  alb = {
    web = {
      internal                          = false
      load_balancer_type                = "application"
      security_groups                   = [aws_security_group.alb_web.id]
      subnets                           = [for v in aws_subnet.this : v.id if v.tags.Role == "public"]

      idle_timeout                      = 60
      enable_cross_zone_load_balancing  = true
      enable_http2                      = true
      enable_deletion_protection        = false
      # enable_deletion_protection       = true
      enable_access_log                 = false 
    }
  }

  listener = {
    web-http = {
      load_balancer_arn = aws_lb.this["web"].arn
      port              = 80
      protocol          = "HTTP"
      ssl_policy        = null
      certificate_arn   = null

      default_action = [{
        default_action_type      = "forward"
        default_target_group_arn = aws_lb_target_group.this["web-http-01"].arn
      }]
    }
    web-http-test = {
      load_balancer_arn = aws_lb.this["web"].arn
      port              = 8080
      protocol          = "HTTP"
      ssl_policy        = null
      certificate_arn   = null

      default_action = [{
        default_action_type      = "forward"
        default_target_group_arn = aws_lb_target_group.this["web-http-01"].arn
      }]
    }

  }

  target_group = {
    web-http-01 = {
      port                              = 80
      protocol                          = "HTTP"
      target_type                       = "ip"
      vpc_id                            = aws_vpc.this.id
      deregistration_delay              = 60
      health_check_enabled              = true
      health_check_interval             = 30
      health_check_path                 = "/"
      health_check_port                 = "traffic-port" # トラフィックを受信するポートを使用。デフォルト。
      health_check_protocol             = "HTTP"
      health_check_timeout              = 5
      health_check_healthy_threshold    = 3
      health_check_unhealthy_threshold  = 3
      health_check_matcher              = "200"
      stickiness_enabled                = false
      stickiness_type                   = "lb_cookie"
      stickiness_cookie_duration        = 86400 # session_typeをlb_cookieに指定した時のみ指定可能
      # stickiness_cookie_name     = "cookie"  # session_typeをapp_cookieに指定した時のみ指定可能
    }

    web-http-02 = {
      port                              = 80
      protocol                          = "HTTP"
      target_type                       = "ip"
      vpc_id                            = aws_vpc.this.id
      deregistration_delay              = 60
      health_check_enabled              = true
      health_check_interval             = 30
      health_check_path                 = "/"
      health_check_port                 = "traffic-port" # トラフィックを受信するポートを使用。デフォルト。
      health_check_protocol             = "HTTP"
      health_check_timeout              = 5
      health_check_healthy_threshold    = 3
      health_check_unhealthy_threshold  = 3
      health_check_matcher              = "200"
      stickiness_enabled                = false
      stickiness_type                   = "lb_cookie"
      stickiness_cookie_duration        = 86400 # session_typeをlb_cookieに指定した時のみ指定可能
      # stickiness_cookie_name     = "cookie"  # session_typeをapp_cookieに指定した時のみ指定可能
    }
  }
}

#####################################################################################################################################################################
###
### main
###
#####################################################################################################################################################################

################################################
### LoadBalancer
################################################
resource "aws_lb" "this" {
  for_each = local.alb

  name               = "${var.project_name}-${var.env}-${each.key}"
  internal           = each.value.internal
  load_balancer_type = each.value.load_balancer_type
  security_groups    = each.value.security_groups

  idle_timeout                     = each.value.idle_timeout
  subnets                          = each.value.subnets
  enable_cross_zone_load_balancing = each.value.enable_cross_zone_load_balancing
  enable_http2                     = each.value.enable_http2
  enable_deletion_protection       = each.value.enable_deletion_protection

  tags = {
    Name = "${var.project_name}-${var.env}-${each.key}"
  }
}

################################################
### Target Group
################################################
resource "aws_lb_target_group" "this" {
  for_each = local.target_group

  name                 = "${var.project_name}-${var.env}-${each.key}"
  port                 = each.value.port
  protocol             = each.value.protocol
  vpc_id               = aws_vpc.this.id
  deregistration_delay = each.value.deregistration_delay
  target_type          = each.value.target_type

  health_check {
    enabled             = each.value.health_check_enabled
    interval            = each.value.health_check_interval
    path                = each.value.health_check_path
    port                = each.value.health_check_port # トラフィックを受信するポートを使用。デフォルト。
    protocol            = each.value.health_check_protocol
    timeout             = each.value.health_check_timeout
    healthy_threshold   = each.value.health_check_healthy_threshold
    unhealthy_threshold = each.value.health_check_unhealthy_threshold
    matcher             = each.value.health_check_matcher
  }

  stickiness {
    enabled         = try(each.value.stickiness_enabled, null)
    type            = try(each.value.stickiness_type, null)
    cookie_duration = try(each.value.stickiness_cookie_duration, null)
    cookie_name     = try(each.value.stickiness_cookie_name, null)
  }

  tags = {
    Name = "${var.project_name}-${var.env}-${each.key}"
  }
}

################################################
### Listenr
################################################
resource "aws_lb_listener" "this" {
  for_each = { for k, v in local.listener : k => v }

  load_balancer_arn = each.value["load_balancer_arn"]
  port              = each.value["port"]
  protocol          = each.value["protocol"]
  ssl_policy        = each.value["ssl_policy"]
  certificate_arn   = each.value["certificate_arn"]

  dynamic "default_action" {
    for_each = { for k, v in each.value.default_action : k => v if v.default_action_type == "forward" }

    content {
      type             = default_action.value.default_action_type
      target_group_arn = default_action.value.default_target_group_arn
    }
  }

  dynamic "default_action" {
    for_each = { for k, v in each.value.default_action : k => v if v.default_action_type == "redirect" }

    content {
      type = "redirect"

      redirect {
        port        = default_action.value.default_port
        protocol    = default_action.value.default_protocol
        status_code = default_action.value.default_status_code
      }
    }
  }

  dynamic "default_action" {
    for_each = { for k, v in each.value.default_action : k => v if v.default_action_type == "fixed-response" }

    content {
      type = "fixed-response"

      fixed_response {
        content_type  = default_action.value.content_type
        message_body  = default_action.value.message_body
        status_code   = default_action.value.status_code
      }
    }
  }
}


#####################################################################################################################################################################
###
### sub
###
#####################################################################################################################################################################

################################################
### Security Group
################################################
resource "aws_security_group" "alb_web" {
  name        = "${var.project_name}-${var.env}-sg-alb-web"
  description = "${var.project_name} Security group for ALB (fargate web)"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }


  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  tags = {
    Name = "${var.project_name}-${var.env}-sg-alb"
  }
}


