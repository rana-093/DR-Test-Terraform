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
