terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

locals {
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b"]
}

# VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

# Public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-${element(local.availability_zones, count.index)}-public-subnet"
    Environment = "${var.environment}"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-${element(local.availability_zones, count.index)}-private-subnet"
    Environment = "${var.environment}"
  }
}

#Internet gateway
resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name"        = "${var.environment}-igw"
    "Environment" = var.environment
  }
}

# Elastic-IP (eip) for NAT
# resource "aws_eip" "nat_eip" {
#   vpc        = true
#   depends_on = [aws_internet_gateway.ig]
# }

# # NAT Gateway
# resource "aws_nat_gateway" "nat" {
#   allocation_id = aws_eip.nat_eip.id
#   subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
#   tags = {
#     Name        = "nat-gateway-${var.environment}"
#     Environment = "${var.environment}"
#   }
# }

# Routing tables to route traffic for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}

# Routing tables to route traffic for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}

# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

# Route for NAT Gateway
# resource "aws_route" "private_internet_gateway" {
#   route_table_id         = aws_route_table.private.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_nat_gateway.nat.id
# }

# Route table associations for both Public & Private Subnets
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "console" {
  name_prefix = "console-sg"
  vpc_id = aws_vpc.vpc.id


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH access from any source (Note: This should be restricted to your IP range in production)
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "Console Security Group"
  }
}

resource "aws_security_group" "http_s" {
  name_prefix = "http/https-sg"
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP/S Security Group"
  }
}

# resource "aws_key_pair" "deployer" {
#   key_name   = "demo"
#   public_key = file("~/Downloads/dr.pem")  # Use the file() function to read the PEM file
# }

# resource "aws_instance" "example_ec2" {
#   ami                    = "ami-0f5ee92e2d63afc18"  # Replace with your desired AMI ID
#   instance_type          = "t2.micro"
#   subnet_id              = aws_subnet.public_subnet[0].id
#   associate_public_ip_address = true  # Assigns a public IP address to the instance
#   key_name               = aws_key_pair.deployer.key_name

#   # Security Group settings
#   security_groups        = [aws_security_group.console.id, aws_security_group.http_s.id]

#   tags = {
#     Name = "Example Instance"
#   }
# }

resource "aws_security_group" "rds_sg" {
  name_prefix = "rds-sg-"
  vpc_id      = aws_vpc.vpc.id

  # Allow inbound traffic for MySQL from specific sources
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_subnet_group" "dr_db_subnet_group" {
  name       = "example-db-subnet-group"
  subnet_ids = aws_subnet.private_subnet.*.id  # Use the private subnet for the RDS instance
}


resource "aws_db_instance" "sc_uat_read_replica_DR_Test" {
  allocated_storage    = 20  # Adjust as needed
  engine               = "mysql"
  engine_version       = "8.0.28"  # Change to your desired version
  instance_class       = "db.t3.small"  # Adjust as needed
  identifier           = "dr-test"
  db_name              = "sc_21_04_11"
  username             = "root"  # Change to your desired username
  password             = "a3Lqziu2vqnAun"  # Change to your desired password
  db_subnet_group_name = aws_db_subnet_group.dr_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
}

# Create an Elastic Load Balancer
resource "aws_lb" "my_elb" {
  name               = "my-elb"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public_subnet.*.id  # Replace with your public subnet IDs in ap-south-1
}

# Create listeners for the ELB
resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.my_elb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group_8080.arn
  }
}

# *********************  Should be mumbai specific **********************
# resource "aws_lb_listener" "listener_https" {
#   load_balancer_arn = aws_lb.my_elb.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06	" 
#   certificate_arn   = "arn:aws:elasticloadbalancing:me-south-1:234187612613:listener/app/sc-prod/d7edf8b1aba84a29/936e430fa5e563c3"
#   default_action {
#     type = "forward"
#     target_group_arn = aws_lb_target_group.target_group_8080.arn
#   }
# }

resource "aws_lb_listener" "listener_8080" {
  load_balancer_arn = aws_lb.my_elb.arn
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target_group_8080.arn
  }
}

resource "aws_lb_target_group" "target_group_8080" {
  name        = "target-group-8080"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id  # Replace with your VPC ID
  target_type = "ip"
}

# Create an ECS cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "dr-test"
}

# resource "aws_ecr_repository" "my_ecr_repo" {
#   name = "dr-test-repo"
#   image_tag_mutability = "MUTABLE"  # Optional: Set to "IMMUTABLE" if you want to enforce immutability
#   # scan_on_push = true  # Optional: Set to false if you don't want images to be scanned on push
#   tags = {
#     Environment = "dr-test"
#     Project     = "dr-test"
#   }
# }

resource "aws_elasticache_subnet_group" "dr_cache_subnet_group" {
  name       = "dr-cache-subnet-group"
  subnet_ids = aws_subnet.private_subnet.*.id  # Replace with your subnet IDs
}

resource "aws_security_group" "cache_security_group" {
  name_prefix = "cache-sg"
  description = "ElastiCache security group"

  ingress {
    from_port   = 6379
    to_port     = 6379
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

#Redis Cluster using TF
resource "aws_elasticache_cluster" "dr_cache_cluster" {
  cluster_id           = "dr-cache-cluster"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.dr_cache_subnet_group.name
  security_group_ids   = [aws_security_group.cache_security_group.id]
}

# ***

# Create a task definition for your ECS service (replace the placeholder with your task definition configuration)
# resource "aws_ecs_task_definition" "ecs_task_definition" {
#   family                = "dr-test"
#   container_definitions = <<DEFINITION
# [
#   {
#     "name": "my-container",
#     "image": "my-container-image:latest",
#     "portMappings": [
#       {
#         "containerPort": 80,
#         "hostPort": 0,
#         "protocol": "tcp"
#       }
#     ]
#     // Add more configuration here if needed
#   }
# ]
# DEFINITION
# }

# # Create an ECS service
# resource "aws_ecs_service" "ecs_service" {
#   name            = "my-ecs-service"
#   cluster         = aws_ecs_cluster.ecs_cluster.id
#   task_definition = aws_ecs_task_definition.ecs_task_definition.arn
#   desired_count   = 1

#   network_configuration {
#     subnets          = ["subnet-1a", "subnet-1b", "subnet-1c"]  # Replace with your private subnet IDs in ap-south-1
#     security_groups  = [aws_security_group.ecs_service_sg.id]
#     assign_public_ip = false

#     # Attach the appropriate target group based on the listener port
#     target_group_arn = aws_lb_target_group.target_group_https.arn  # Use HTTPS target group for port 443
#   }

#   deployment_controller {
#     type = "ECS"
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.target_group_https.arn  # Use HTTPS target group for port 443
#     container_name   = "my-container"
#     container_port   = 80
#   }
# }

# # Define a health check for the target group
# resource "aws_lb_target_group_attachment" "target_group_attachment" {
#   target_group_arn = aws_lb_target_group.target_group_https.arn  # Use HTTPS target group for port 443
#   target_id        = aws_ecs_service.ecs_service.id
# }