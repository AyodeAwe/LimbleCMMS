locals {
  main_container_definition = [
    {
      essential = true
      image     = "configured-by-github-actions"
      name      = "${var.service_name}"
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
        }
      ]
    }
  ]
}

resource "aws_security_group" "main" {
  name        = "${var.service_name}-sg"
  description = "Allow ${var.service_name} ports within the VPC, and browsing from the outside"
  vpc_id      = module.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.networking.outputs.vpc_cidr]
    description = "Allow connection to Service Port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outside"
  }

  tags = {
    Name        = "${var.service_name}-sg"
    Terraform   = true
  }

}

resource "aws_security_group" "alb" {
  name        = "${var.service_name}-alb-sg"
  description = "Allow HTTP and HTTPS from the outside"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP to ALB"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS to ALB"
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS to ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.service_name}-alb-sg"
    Terraform   = true
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name               = "${var.service_name}-ecs-role"
  assume_role_policy = file("${path.module}/policies/ecs-assume-role.json")

  tags = {
    Name        = "${var.service_name}-ecs-role"
    Terraform   = true
  }
}

resource "aws_iam_role_policy" "ecs_execution_policy" {
  name   = "${var.service_name}-execution-policy"
  policy = file("${path.module}/policies/ecs-execution-policy.json")
  role   = aws_iam_role.ecs_execution_role.id
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.service_name}-task-role"
  assume_role_policy = file("${path.module}/policies/ecs-task-assume-role.json")

  tags = {
    Name        = "${var.service_name}-sg"
    Terraform   = true
  }
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name   = ""${var.service_name}-policy"
  policy = file("${path.module}/policies/ecs-task-policy.json")
  role   = aws_iam_role.ecs_task_role.id
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.service_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  container_definitions    = jsonencode(local.main_container_definition)
  execution_role_arn       = resource.aws_iam_role.ecs_execution_role.arn
  task_role_arn            = resource.aws_iam_role.ecs_task_role.arn

  tags = {
    Name        = "${var.service_name}"
    Terraform   = true
  }

  lifecycle {
    ignore_changes = [
      container_definitions
    ]
  }
}

resource "aws_ecs_service" "main" {
  name          = "${var.service_name}-svc"
  cluster       = "wordpress-cluster"
  desired_count = 1

  network_configuration {
    subnets          = data.terraform_remote_state.networking.outputs.subnets_private
    security_groups  = [aws_security_group.main.id]
    assign_public_ip = false
  }

  platform_version       = var.ecs_platform_version
  scheduling_strategy    = var.ecs_scheduling_strategy
  enable_execute_command = lookup(var.enable_execute_command, local.workspace)

  task_definition = "${resource.aws_ecs_task_definition.main.family}:${resource.aws_ecs_task_definition.main.revision}"

  load_balancer {
    target_group_arn = aws_lb_target_group.main.*.arn[0]
    container_name   = "${var.service_name}-sg"
    container_port   = var.container_port
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  lifecycle {
    ignore_changes = [
      desired_count,
      load_balancer,
      task_definition
    ]
  }

  tags = {
    Name        = "${var.service_name}"
    Terraform   = true
  }
}

resource "aws_appautoscaling_target" "main" {
  service_namespace  = "ecs"
  resource_id        = "service/${resource.aws_ecs_service.main.cluster}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  role_arn           = lookup(var.service_role_autoscaling, local.workspace)
  min_capacity       = lookup(var.min_capacity, local.workspace)
  max_capacity       = lookup(var.max_capacity, local.workspace)

  lifecycle {
    ignore_changes = [
      role_arn
    ]
  }
}

resource "aws_appautoscaling_policy" "cpu" {
  count              = 1
  name               = "ecs_scale_cpu"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 75
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }

  depends_on = [aws_appautoscaling_target.main]
}

resource "aws_appautoscaling_policy" "memory" {
  count              = 1
  name               = "ecs_scale_memory"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 75
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }

  depends_on = [
    aws_appautoscaling_target.main
  ]
}