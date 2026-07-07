# Terraform Infrastructure as Code (IaC)

This directory contains the Terraform configuration files to provision a secure, highly available, multi-tier web application architecture on AWS.

## Directory Layout

*   [`versions.tf`](versions.tf): Configures the required Terraform and provider versions.
*   [`providers.tf`](providers.tf): Declares the AWS provider configuration and global resource tagging logic.
*   [`variables.tf`](variables.tf): Outlines configuration inputs, including networking sizes, compute instance types, database details, and DNS settings.
*   [`main.tf`](main.tf): Defines the networking (VPC, Subnets, Routing, NAT), security policies (IAM, Security Groups), compute layer (Launch Template, ASG, ALB), storage layer (S3), database tier (Multi-AZ RDS), and operations (CloudWatch Alarms).
*   [`outputs.tf`](outputs.tf): Defines standard resource references (VPC IDs, Load Balancer URLs) emitted post-deployment.
*   [`terraform.tfvars.example`](terraform.tfvars.example): A template configuration file containing sample parameters.

---

## Deployment Steps

To run this Terraform code, follow the instructions below:

### 1. Prerequisites
Ensure you have the following installed and configured locally:
*   [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) (>= 1.5.0)
*   [AWS CLI](https://aws.amazon.com/cli/) with configure profile credentials (`aws configure`) that possess administrator permissions to provision these resources.

### 2. Copy Local Variables
Initialize your local variables file by copying the template:
```bash
cp terraform.tfvars.example terraform.tfvars
```
*Open `terraform.tfvars` and customize your database password and other variables as needed.*

### 3. Initialize Terraform
Downloads the required AWS provider plugin:
```bash
terraform init
```

### 4. Format and Validate Code
Verify syntax and format:
```bash
terraform fmt -check
terraform validate
```

### 5. Generate Execution Plan
Run a dry run execution plan to review the resource modifications:
```bash
terraform plan -out=tfplan
```

### 6. Apply Infrastructure Changes
Provision the AWS infrastructure (this takes roughly 10-15 minutes, mostly for the RDS and NAT Gateway resources):
```bash
terraform apply tfplan
```

---

## Clean Up (Teardown)

To avoid incurring ongoing charges, destroy the created resources when done:
```bash
terraform destroy -auto-approve
```
*Note: Make sure your S3 bucket is empty prior to tearing down, or configure `force_destroy = true` as currently defined in `main.tf`.*
