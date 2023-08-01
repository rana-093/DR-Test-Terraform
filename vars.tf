variable "aws_region" {
  default = "ap-south-1"
}

variable "environment" {
  default = "dr-test"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "CIDR block of the vpc"
}

variable "public_subnets_cidr" {
  type        = list(any)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR block for Public Subnet"
}

variable "private_subnets_cidr" {
  type        = list(any)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR block for Private Subnet"
}

variable "spring_profile" {
  default     = "drtest"
}