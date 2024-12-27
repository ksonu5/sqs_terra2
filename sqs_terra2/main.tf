provider "aws" {
  region = "ap-south-1"
}

# Create an ECR repository
resource "aws_ecr_repository" "flask_api_repo" {
  name = "flask-api-repo"
}

# ECS Cluster
resource "aws_ecs_cluster" "flask_api_cluster" {
  name = "flask-api-cluster"
}

# VPC and Subnets
data "aws_availability_zones" "available" {
  
}
resource "aws_vpc" "flask_api_vpc" {
  cidr_block = "172.31.0.0/16"
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.flask_api_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.flask_api_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)  # Use different AZs
}



# Security Group for ECS Service
resource "aws_security_group" "flask_api_sg" {
  name_prefix = "flask-api-sg"
  vpc_id      = aws_vpc.flask_api_vpc.id

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internet Gateway for the VPC
resource "aws_internet_gateway" "flask_api_igw" {
  vpc_id = aws_vpc.flask_api_vpc.id
}



# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Definition
resource "aws_ecs_task_definition" "flask_api_task" {
  family                   = "flask-api-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "flask-api"
      image     = "${aws_ecr_repository.flask_api_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "flask_api_service" {
  name            = "flask-api-service"
  cluster         = aws_ecs_cluster.flask_api_cluster.id
  task_definition = aws_ecs_task_definition.flask_api_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.public.*.id
    security_groups = [aws_security_group.flask_api_sg.id]
    assign_public_ip = true
  }
  desired_count = 1
}

# Load Balancer
resource "aws_lb" "flask_api_lb" {
  name               = "flask-api-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.flask_api_sg.id]
  subnets            = aws_subnet.public.*.id
}

resource "aws_lb_target_group" "flask_api_tg" {
  name     = "flask-api-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.flask_api_vpc.id
}

resource "aws_lb_listener" "flask_api_listener" {
  load_balancer_arn = aws_lb.flask_api_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_api_tg.arn
  }
}

# Output Public URL
output "public_url" {
  value = aws_lb.flask_api_lb.dns_name
}
