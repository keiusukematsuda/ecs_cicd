#####################################################################################################################################################################
###
### Summary : ECS Fargate
###
#####################################################################################################################################################################
# - Resource
#   - main
#     - Cluster
#     - Capacity Provider
#     - Task Definition
#     - Service
#   - sub 
#     - IAM Role
#     - Security Group

#####################################################################################################################################################################
###
### Parameter
###
#####################################################################################################################################################################

locals {
  cluster = {
    web01 = {
      container_insight = "enabled"
    }
  }
  taskdef = {
    web = {
      cpu            = 256
      memory         = 1024
      container_name = "${var.project_name}-${var.env}-container-web"
    }
  }
  service = {
    web = {
        cluster             = "web01"
        task_desire_count   = 1 
        deploy_type         = "CODE_DEPLOY" # ローリングデプロイの時はECS、Blue-Greenデプロイメントの場合はCODE_DEPLOY
        subnets             = [for v in aws_subnet.this : v.id if v.tags.Role == "protected"]
        security_groups     = [aws_security_group.ecs.id]
        assign_public_ip    = false
        load_balancer = {
            web = {
                target_group_arn    = aws_lb_target_group.this["web-http-01"].arn
                container_name      = "${var.project_name}-${var.env}-container-web"
                container_port      = 80
            }
        }
    }

  }
  iam_roles = {
    task-execution = {
      principals = ["ecs-tasks.amazonaws.com"],
      policys = [
        "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"

      ]
    },
    task = {
      principals = ["ecs-tasks.amazonaws.com"]
      policys = [
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
      ]
    },
    service = {
      principals = ["ecs.amazonaws.com"]
    }
  }
  iam_policies = {
    service = {
      file = "service.json"
    }
    task = {
      file = "task.json"
    }
  }
}

#####################################################################################################################################################################
###
### main
###
#####################################################################################################################################################################

################################################
### Cluster
################################################
resource "aws_ecs_cluster" "fargate" {
  for_each = local.cluster

  name = "${var.project_name}-${var.env}-cluster-${each.key}"

  setting {
    name  = "containerInsights"
    value = each.value.container_insight
  }

  tags = {
    Name  = "${var.project_name}-${var.env}-cluster-${each.key}"
  }
}

################################################
### Capacity Provider
################################################
resource "aws_ecs_cluster_capacity_providers" "fargate" {
  for_each = local.cluster

  cluster_name       = "${var.project_name}-${var.env}-cluster-${each.key}"
  capacity_providers = ["FARGATE"]

  depends_on = [
    aws_ecs_cluster.fargate
  ]  
}

################################################
### Task Definition
################################################
resource "aws_ecs_task_definition" "fargate" {
  for_each = local.taskdef

  family                   = "${var.project_name}-${var.env}-taskdef-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  container_definitions    = templatefile("${path.module}/ecs-fargate/taskdef/${each.key}.json", { 
    container_name  = each.value.container_name,
    account_id      = var.account_id
    image_uri       = var.image_uri
    }
  )
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  task_role_arn      = aws_iam_role.ecs["task"].arn
  execution_role_arn = aws_iam_role.ecs["task-execution"].arn

#タスク定義をCICDで更新する場合などはIgnoreする
  # lifecycle {
  #   ignore_changes = [
  #     container_definitions
  #     ]
  # }

}

################################################
### Service
################################################
resource "aws_ecs_service" "fargate" {
  for_each = local.service
  name                    = "${var.project_name}-${var.env}-fargate-service-${each.key}"
  cluster                 = aws_ecs_cluster.fargate["${each.value.cluster}"].id
  task_definition         = aws_ecs_task_definition.fargate["${each.key}"].arn
  desired_count           = each.value.task_desire_count
  launch_type             = "FARGATE"
  enable_execute_command  = true    

  deployment_controller {
    type = each.value.deploy_type
  }


  dynamic "load_balancer" {
    for_each = each.value.load_balancer

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  network_configuration {
    subnets          = each.value.subnets
    security_groups  = each.value.security_groups
    assign_public_ip = each.value.assign_public_ip
  }

#タスク定義をCICDで更新する場合などはIgnoreする
  # lifecycle {
  #   ignore_changes = [task_definition]
  # }

}

#####################################################################################################################################################################
###
### sub
###
#####################################################################################################################################################################
################################################
### IAM Role
################################################
data "aws_iam_policy_document" "ecs" {
  for_each = local.iam_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"

      identifiers = each.value.principals
    }
  }
}

resource "aws_iam_policy" "ecs" {
  for_each = local.iam_policies

  name   = "${var.project_name}-${var.env}-policy-${each.key}"
  policy = file("${path.module}/iam_policies/${each.value.file}")
}

resource "aws_iam_role" "ecs" {
  for_each = local.iam_roles

  name               = "${var.project_name}-${var.env}-role-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ecs[each.key].json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  for_each = toset(local.iam_roles.task-execution.policys)

  role       = aws_iam_role.ecs["task-execution"].name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "ecs_task" {
  for_each = toset(local.iam_roles.task.policys)

  role       = aws_iam_role.ecs["task"].name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "ecs_task_from_json" {
  role       = aws_iam_role.ecs["task"].name
  policy_arn = aws_iam_policy.ecs["task"].arn
}

resource "aws_iam_role_policy_attachment" "ecs_service" {
  role       = aws_iam_role.ecs["service"].name
  policy_arn = aws_iam_policy.ecs["service"].arn
}


################################################
### Security Group
################################################

### Web
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-${var.env}-sg-ecs-fargate"
  description = "${var.project_name} Security group for ECS Fargate"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    security_groups = [
      aws_security_group.alb_web.id
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
    Name = "${var.project_name}-${var.env}-sg-ecs-fargate"
  }
}