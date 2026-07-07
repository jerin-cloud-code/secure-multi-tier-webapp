variable "aws_region" {
  type        = string
  description = "The target AWS Region for deployment"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "The prefix to apply to all resources"
  default     = "secure-multi-tier"
}

variable "environment" {
  type        = string
  description = "Deployment environment name (e.g. dev, staging, prod)"
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the custom VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the public ALB subnets (must be exactly 2)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the private app tier subnets (must be exactly 2)"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the private db tier subnets (must be exactly 2)"
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "instance_type" {
  type        = string
  description = "EC2 instance size for the web application servers"
  default     = "t3.micro"
}

variable "ami_id" {
  type        = string
  description = "Static placeholder AMI ID for launching EC2 instances (AMIs are region-specific)"
  default     = "ami-0c7217cdde317cfec" # Example Amazon Linux 2023 AMI in us-east-1
}

variable "db_allocated_storage" {
  type        = number
  description = "RDS DB instance storage size (in GB)"
  default     = 20
}

variable "db_instance_class" {
  type        = string
  description = "RDS DB instance compute size"
  default     = "db.t3.micro"
}

variable "db_name" {
  type        = string
  description = "The database name to instantiate on the RDS cluster"
  default     = "appdb"
}

variable "db_username" {
  type        = string
  description = "The master username for the database"
  default     = "dbadmin"
}

variable "db_password" {
  type        = string
  description = "The master password for the database. Must be marked sensitive."
  sensitive   = true
}

variable "domain_name" {
  type        = string
  description = "The domain name for DNS and TLS setup (e.g. portfolio.example.com)"
  default     = "example.com"
}
