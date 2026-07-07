# Security Controls & Compliance

This document outlines the security controls implemented in the `secure-multi-tier-webapp` project. It highlights network security boundaries, identity principles, encryption standards, operational visibility, and suggestions for production-ready hardening.

---

## 1. Network Security Controls

*   **Subnet Segmentation**: The architecture implements distinct network zones. Public subnets only host the ALB nodes and NAT Gateways. Application servers and database clusters are placed inside private subnets, ensuring no direct ingress is possible from the internet.
*   **Layered Security Groups (Least Privilege)**:
    *   **ALB Security Group**: Open to the public internet (`0.0.0.0/0`) on ports `80` (HTTP) and `443` (HTTPS) to serve users.
    *   **Web App Security Group**: Blocked from all public ingress. Ingress is restricted to Port `80` from the ALB security group ID only. Egress is allowed to route updates via the NAT Gateways.
    *   **DB Security Group**: Strict ingress restricted to Port `3306` (MySQL) from the Web App security group ID only. Egress is disabled (`127.0.0.1/32` dummy endpoint) to prevent database servers from initiating outbound network calls, mitigating data exfiltration risks.
*   **Database Route Table Isolation**: Unlike the App private subnets, which route out to the internet through the NAT Gateway, the DB private subnets have **no route** to the internet. They are network-isolated.

---

## 2. IAM Controls (Identity & Access Management)

*   **Credential-Free Compute**: No static AWS Access Keys or Secret Keys are stored on the EC2 instances.
*   **IAM Instance Profiles**: The EC2 instances are attached to an IAM Instance Profile linked to an IAM role.
*   **Least-Privilege Policy**: The IAM role has a single policy attachment: `AmazonSSMManagedInstanceCore`. This grants the instance permissions to connect to AWS Systems Manager for secure shell access, inventory management, and patch verification. It grants no permissions to create or alter other AWS resources.
*   **SSM Session Manager (No SSH Key Pairs)**: The EC2 Launch Template is configured without an SSH key pair (`key_name` is omitted), and Port 22 is closed on all security groups. Admin sessions are managed via AWS Systems Manager Session Manager, which encrypts traffic, validates authentication via IAM, and records commands to CloudWatch.
*   **IMDSv2 Enforced**: The EC2 Launch Template enforces the use of Instance Metadata Service Version 2 (`http_tokens = "required"`), protecting the instance credentials from Server-Side Request Forgery (SSRF) vulnerabilities.

---

## 3. Data Protection & Encryption

*   **Encryption at Rest**:
    *   **RDS Database Storage**: Storage encryption is enabled (`storage_encrypted = true`) on the RDS MySQL database using the default AWS managed KMS key for RDS. All tables, backups, and transaction logs are encrypted.
    *   **S3 Logs Bucket**: The S3 bucket enforces server-side encryption (`AES256`) for all stored objects and blocks all public ACLs/policies via an S3 Public Access Block configuration.
    *   **EC2 EBS Volumes**: Root block devices on the launch template have encryption enabled (`encrypted = true`) using the AWS-managed KMS key for EBS.
*   **Encryption in Transit**:
    *   **S3 Secure Transport**: An S3 bucket policy is attached that denies any request that does not utilize HTTPS (`aws:SecureTransport = false`).
    *   **ALB HTTPS Listener**: The architecture outline describes an HTTPS listener on port 443. The application is designed to terminate TLS at the ALB using certificates generated and rotated in AWS Certificate Manager (ACM).

---

## 4. Secrets Handling

*   **No Hardcoded Credentials**: Database passwords and master usernames are handled dynamically using Terraform variables.
*   **Sensitive Variables**: The `db_password` variable is marked `sensitive = true` in variables.tf. This prevents Terraform from printing the password in plain text during `terraform plan` or `terraform apply` commands.
*   **Secrets Manager (Production Recommendation)**: In a true production deployment, we would replace the variable-driven database credential with a dynamic lookup using **AWS Secrets Manager**.
    *   *Mechanism*: Terraform creates the secret in Secrets Manager, RDS is provisioned utilizing the secret credentials, and the EC2 instances retrieve the credentials dynamically at runtime using their IAM Instance Profile. This eliminates passwords from TF state files.

---

## 5. Security Limitations of This Demo Architecture

*   **Local State Storage**: The Terraform state file (`terraform.tfstate`) contains the raw database master password in plain text. (This is a standard Terraform limitation for local states).
*   **HTTP Fallback Enabled**: The default listener is configured on Port 80 for demo purposes to avoid requiring a valid DNS domain name registration to deploy ACM.
*   **Default KMS Keys**: Uses AWS-managed KMS keys rather than custom customer managed keys (CMKs), which prevents granular key rotation and access policies.

---

## 6. Production Hardening Recommendations

To promote this architecture to a production-grade enterprise deployment, implement the following security enhancements:

1.  **Configure Remote Backend State**: Use an S3 backend with DynamoDB locking. Enforce server-side encryption and strict IAM access controls on the S3 state bucket.
2.  **Transition to AWS Secrets Manager**: Automatically rotate the database password using an AWS Lambda function integrated with Secrets Manager.
3.  **Implement AWS WAF (Web Application Firewall)**: Attach AWS WAF to the Application Load Balancer to protect the application from common web exploits (SQL injection, Cross-Site Scripting, DDoS attacks).
4.  **Use Customer Managed Keys (CMKs)**: Provision custom KMS keys with defined key rotation policies for EBS, S3, and RDS encryption.
5.  **Enforce Strict HTTPS Redirects**: Force all port 80 traffic on the ALB to redirect to port 443, utilizing an ACM TLS certificate.
6.  **VPC Flow Logs**: Enable VPC Flow Logs on the custom VPC, sending network flows to CloudWatch Logs or an S3 bucket for security analysis and anomaly detection.
7.  **Enable AWS GuardDuty**: Enable GuardDuty in the account to monitor for malicious activity, resource compromise, and brute-force attempts.
