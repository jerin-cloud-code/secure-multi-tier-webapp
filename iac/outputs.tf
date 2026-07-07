output "vpc_id" {
  description = "The ID of the custom VPC"
  value       = aws_vpc.main.id
}

output "public_subnets" {
  description = "List of IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_app_subnets" {
  description = "List of IDs of the private app subnets"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnets" {
  description = "List of IDs of the private db subnets"
  value       = aws_subnet.private_db[*].id
}

output "alb_dns_name" {
  description = "The public-facing DNS name of the Application Load Balancer"
  value       = aws_lb.external.dns_name
}

output "rds_endpoint" {
  description = "The database connectivity endpoint (excluding port)"
  value       = aws_db_instance.database.endpoint
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket created for static assets and logs"
  value       = aws_s3_bucket.assets.id
}
