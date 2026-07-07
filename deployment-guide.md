# Deployment Guide

This guide describes how to initialize, format, validate, plan, deploy, and tear down the infrastructure defined in this repository.

---

## 1. Prerequisites

Before starting, ensure you have the following installed on your local machine:

1.  **Terraform CLI** (v1.5.0 or newer): [Install Terraform](https://developer.hashicorp.com/terraform/downloads).
2.  **AWS CLI**: [Install AWS CLI](https://aws.amazon.com/cli/).
3.  **Active AWS Account**: Ensure you have administrator access to provision resources.
4.  **AWS Credentials Configuration**: Configure credentials by running:
    ```bash
    aws configure
    ```
    *Input your AWS Access Key, Secret Access Key, Default Region (e.g. `us-east-1`), and Output format (`json`).*

---

## 2. Step-by-Step Deployment

All commands must be executed from the `iac/` directory of the project.

### Step A: Initialize the Workspace
Initialize the working directory to download the required AWS provider version defined in `versions.tf`:
```bash
cd iac
terraform init
```

### Step B: Configure Local Variables
Create a local `terraform.tfvars` file by copying the provided example template:
```bash
cp terraform.tfvars.example terraform.tfvars
```
Open `terraform.tfvars` in a text editor and modify the following variables:
*   Set a secure `db_password` (Must be at least 8 characters).
*   Change the `project_name` or `environment` value if deploying alongside existing projects.
*   Update `domain_name` to your target placeholder (e.g., `app.yourname.com`).

### Step C: Lint and Format Code
Ensure code formatting matches the HashiCorp standards:
```bash
terraform fmt -recursive
```

### Step D: Validate Code Syntax
Validate the configuration files for syntactical and logical errors without connecting to AWS:
```bash
terraform validate
```

### Step E: Create an Execution Plan
Generate and save an execution plan. Review the console output to see the 24+ resources Terraform plans to create:
```bash
terraform plan -out=tfplan
```
*Verify that no secrets or plain text passwords are being hardcoded in the outputs.*

### Step F: Apply the Configuration
Apply the plan to create the resources in AWS:
```bash
terraform apply tfplan
```
*This process takes between 8 to 15 minutes, primarily driven by the provisioning of the Multi-AZ RDS instance and the NAT Gateways.*

---

## 3. Safe Deployment Notes

*   **State Management**: For a local demonstration, the Terraform state is stored locally in the `terraform.tfstate` file. Do **not** commit this file to git. For production use, configure a remote state backend (e.g. S3 backend with DynamoDB state locking).
*   **Variable Isolation**: Never hardcode credentials in `main.tf`. Use the `terraform.tfvars` file which is explicitly ignored by our `.gitignore`.
*   **Default S3 Naming**: The S3 bucket name is set to include a random suffix (e.g., `secure-multi-tier-dev-logs-assets-12345`). S3 bucket names are globally unique; modify this in `main.tf` if a naming collision occurs.

---

## 4. Teardown Instructions (Destroy)

To prevent incurring unnecessary AWS charges, tear down the infrastructure once you have completed your testing.

Run the following command in the `iac/` directory:
```bash
terraform destroy -auto-approve
```

> [!IMPORTANT]
> The S3 bucket configured in `main.tf` has versioning enabled and is designed to block non-SSL traffic. If you uploaded any objects or access logs were written to the bucket, ensure the bucket is completely empty before executing `terraform destroy`. If the destroy fails on the S3 resource, manually empty the bucket via the AWS Console or AWS CLI and rerun `terraform destroy`.

---

## 5. Troubleshooting Common Issues

### Issue 1: `BucketAlreadyExists` or `BucketAlreadyOwnedByYou`
*   **Symptom**: S3 bucket creation fails during `terraform apply`.
*   **Cause**: S3 buckets are globally unique across all AWS accounts. Another user has registered the bucket name defined in your `terraform.tfvars` or `main.tf` file.
*   **Solution**: Modify the bucket name suffix in `main.tf` (line 157) or expose it as a variable, then rerun `terraform plan` and `terraform apply`.

### Issue 2: RDS Instance Creation Hangs/Timeouts
*   **Symptom**: `aws_db_instance` resource creation exceeds 15 minutes and fails.
*   **Cause**: Usually caused by subnet misconfigurations or AWS service limits/outages in the target AZ.
*   **Solution**: Ensure your CIDR blocks do not overlap. Verify that your DB subnets are correctly assigned to the database subnet group and reside in different AZs.

### Issue 3: EC2 Instances Failing Health Checks
*   **Symptom**: ALB displays target instances as `Unhealthy`.
*   **Cause**: The user data script might still be running, Apache failed to start, or the instance cannot connect to the internet to download packages.
*   **Solution**: 
    1. Connect to the instance using SSM Session Manager.
    2. Check the user data log file: `/var/log/user-data.log` (or check system logs `/var/log/messages`).
    3. Ensure the NAT Gateways are functioning and the private route tables correctly forward `0.0.0.0/0` traffic through the NAT.
