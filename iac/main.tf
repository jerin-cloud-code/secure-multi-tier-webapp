# ==============================================================================
# Locals & Data Sources
# ==============================================================================

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Portfolio   = "secure-multi-tier-webapp"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# Networking (VPC, Subnets, Gateways, Route Tables)
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# Internet Gateway for Public Routing
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# Public Subnets (2 AZs for High Availability ALB)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
    Tier = "Public"
  }
}

# Private App Subnets (2 AZs for Auto Scaling Group)
resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-subnet-${count.index + 1}"
    Tier = "Private App"
  }
}

# Private DB Subnets (2 AZs for Database Cluster)
resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-subnet-${count.index + 1}"
    Tier = "Private DB"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
  }
}

# NAT Gateways (1 per AZ for Redundancy in Production)
resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-gw-${count.index + 1}"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

# Separate Route Tables for each private AZ (routing through local NAT Gateway)
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
  }
}

# Public Subnet Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private App Subnet Associations
resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Private DB Route Table (Isolated; no route to the internet/NAT)
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-rt"
  }
}

# Private DB Subnet Associations (Maintains strict database isolation)
resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.db.id
}

# ==============================================================================
# Security Groups (Layered Least Privilege Boundaries)
# ==============================================================================

# ALB Security Group (Accepts HTTP/HTTPS from Internet)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Controls ingress and egress for the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound to App tier"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# EC2 Web Security Group (Accepts traffic only from ALB)
resource "aws_security_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-sg"
  description = "Controls ingress and egress for EC2 web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTP only from ALB security group"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic (for patching/NAT routing)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-web-sg"
  }
}

# RDS DB Security Group (Accepts traffic only from EC2 Web SG)
resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "Controls ingress and egress for the Database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL traffic from Web tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "Block outbound database requests"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"] # Dummy block; RDS doesn't need to make outgoing connections
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sg"
  }
}

# ==============================================================================
# IAM Profiles (Systems Manager Access - SSH Avoidance)
# ==============================================================================

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ==============================================================================
# S3 Bucket (Access Logs & Static Assets)
# ==============================================================================

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project_name}-${var.environment}-logs-assets-12345" # S3 buckets must be globally unique
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-s3"
  }
}

resource "aws_s3_bucket_versioning" "assets_versioning" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets_encryption" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enforce secure transport (SSL/TLS) for S3
resource "aws_s3_bucket_policy" "enforce_tls" {
  bucket = aws_s3_bucket.assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.assets.arn,
          "${aws_s3_bucket.assets.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Block all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "assets_pab" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==============================================================================
# Compute (Launch Template, Auto Scaling Group, ALB)
# ==============================================================================

# Application Load Balancer
resource "aws_lb" "external" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# ALB Target Group for EC2 Web servers
resource "aws_lb_target_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

# Default HTTP Listener (Port 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.external.arn
  port              = 80
  protocol          = "HTTP"

  # In production, we'd redirect HTTP to HTTPS listener (Port 443)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# EC2 Launch Template (defines AMI, Size, IAM profile, User Data, disk size)
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-${var.environment}-template-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web.id]
  }

  # Basic User Data Script to configure Apache Web Server
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd mariadb105
              systemctl start httpd
              systemctl enable httpd
              
              # Get local metadata for demonstration
              TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
              AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
              
              # Render standard page
              echo "<html><head><title>AWS Secure Webapp Demo</title>" > /var/www/html/index.html
              echo "<style>body { font-family: sans-serif; text-align: center; padding: 50px; background-color: #f4f6f9; color: #232f3e; }</style></head>" >> /var/www/html/index.html
              echo "<body><h1>Secure Multi-Tier Webapp Portfolio Project</h1>" >> /var/www/html/index.html
              echo "<p><strong>Instance ID:</strong> $INSTANCE_ID</p>" >> /var/www/html/index.html
              echo "<p><strong>Availability Zone:</strong> $AVAILABILITY_ZONE</p>" >> /var/www/html/index.html
              echo "<p><strong>DB Endpoint:</strong> ${aws_db_instance.database.endpoint}</p>" >> /var/www/html/index.html
              echo "<hr/><p>Running on AWS - Portfolio Demo Template</p></body></html>" >> /var/www/html/index.html
              EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-launch-template"
  }
}

# Auto Scaling Group (spans both Private Subnets)
resource "aws_autoscaling_group" "web" {
  name_prefix         = "${var.project_name}-${var.environment}-asg-"
  vpc_zone_identifier = aws_subnet.private_app[*].id
  target_group_arns   = [aws_lb_target_group.web.arn]
  force_delete        = true

  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["tag"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-web-server"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Policy: Target Tracking based on CPU Utilization
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project_name}-${var.environment}-cpu-scaling-policy"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.web.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ==============================================================================
# Database (RDS Subnet Group & DB Instance)
# ==============================================================================

resource "aws_db_subnet_group" "db_subnet" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids  = aws_subnet.private_db[*].id
  description = "RDS DB subnet group spanning private subnets"

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

resource "aws_db_instance" "database" {
  identifier        = "${var.project_name}-${var.environment}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # Multi-AZ enabled for high availability (Primary & Standby replica)
  multi_az = true

  # Security configurations
  storage_encrypted = true
  port              = 3306

  # Deletion Protection: Switch to true in production
  deletion_protection = false

  # Backup policies
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:30-Sun:05:30"
  skip_final_snapshot     = true # Set to false in production

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
  }
}

# ==============================================================================
# Operations & Alarms (CloudWatch Setup)
# ==============================================================================

# CloudWatch Log Group for Application/EC2 logs
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}-app-logs"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-log-group"
  }
}

# Alarm: High CPU Util on Auto Scaling Group
resource "aws_cloudwatch_metric_alarm" "asg_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-asg-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggered when average ASG CPU exceeds 80% for 10 minutes"
  actions_enabled     = false # In production, configure SNS ARN here

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

# Alarm: RDS Low Freeable Storage Space
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-low-storage"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5000000000 # 5 GB in bytes
  alarm_description   = "Triggered when RDS storage drops below 5 GB"
  actions_enabled     = false

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.database.identifier
  }
}
