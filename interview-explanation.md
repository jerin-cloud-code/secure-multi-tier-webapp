# Interview Talking Points & Deep-Dive Q&A

This document serves as a study guide for explaining this architecture during technical interviews. It contains elevator pitches tailored for different audiences, a deep dive into the design tradeoffs, and 15 mock interview questions with professional answers.

---

## 1. The Elevator Pitch

### For HR & Non-Technical Recruiters
> "This project demonstrates a standard secure hosting environment on AWS. It uses a three-tier design to separate public traffic from application servers and databases. By placing the servers and database in private subnets, we ensure they cannot be accessed directly from the internet, protecting them against common cyber attacks. Additionally, the setup is highly resilient—if one data center goes offline, the application automatically heals and continues running from a second location without losing database records."

### For DevOps & Technical Interviewers
> "This is a modular, multi-tier web application architecture designed in Terraform. It establishes a custom VPC with public, private app, and private DB subnets across two Availability Zones. Traffic ingress is managed through an Application Load Balancer, which forwards requests to an auto-scaled EC2 compute layer. The database is a Multi-AZ RDS MySQL cluster. Network isolation is enforced at the subnet route table level and via security groups that restrict ingress to the security groups of upstream resources. SSH ports are fully closed; operations and terminal sessions are managed strictly via AWS Systems Manager Session Manager. EBS volumes and RDS instances are encrypted using KMS."

---

## 2. Technical Trade-Offs Analyzed

During interviews, you will often be asked *why* you chose a specific service over another. Here are the rationales for key decisions:

### A. ALB (Application Load Balancer) vs. NLB (Network Load Balancer)
*   **ALB Choice**: We used an ALB because this is a standard HTTP/HTTPS web application. ALBs operate at Layer 7 (Application Layer) and support advanced routing (path-based, host-based routing), SSL/TLS termination, HTTP/2, and integration with AWS WAF.
*   **NLB Alternative**: An NLB operates at Layer 4 (Transport Layer). It is designed for ultra-low latency, handling millions of requests per second, routing TCP/UDP traffic, and providing static IP addresses. Since this application does not require raw TCP routing or static IPs, ALB is the more feature-rich and appropriate choice.

### B. RDS Multi-AZ vs. RDS Read Replicas
*   **Multi-AZ Choice**: This is for **High Availability and Disaster Recovery**. AWS provisions a standby database in a second AZ and performs synchronous replication. If the primary instance fails, failover is automatic.
*   **Read Replicas Alternative**: Read replicas are for **Scalability and Performance**. Replication is asynchronous, and they are used to offload read traffic from the primary database. They do not support automatic failover out of the box in the same way. We prioritized high availability, making Multi-AZ the primary requirement.

### C. NAT Gateway vs. NAT Instance
*   **NAT Gateway Choice**: Managed by AWS, scales up to 100 Gbps, highly available within the AZ, and requires no OS patching or route maintenance.
*   **NAT Instance Alternative**: Run on a single EC2 instance, costing significantly less, but acts as a single point of failure and requires manual patching and bandwidth management. We selected NAT Gateway for the production design, but documented NAT instances as a cost-reduction strategy for labs.

### D. Public vs. Private Subnet Placement
*   **Subnet Partitioning**: We placed only load balancer nodes and NAT Gateways in public subnets (subnets with a route directing `0.0.0.0/0` to the Internet Gateway). Compute and database nodes sit in private subnets. This keeps the attack surface minimal, as public endpoints are heavily restricted and monitored.

### E. Auto Scaling: Target Tracking vs. Scheduled Scaling
*   **Target Tracking Choice**: Scales dynamically based on real-time metrics (e.g. keeping average CPU at 70%). This is highly reactive and optimizes costs based on actual user demand.
*   **Scheduled Scaling Alternative**: Scales based on predictable, known calendar events (e.g., scaling up on Black Friday morning). If user traffic is unpredictable, target tracking is preferred. (In production, you can combine both).

---

## 3. 15 Mock Interview Questions & Answers

### Q1: Why did you split the private subnets into "App" and "DB" tiers instead of just using one private subnet?
*   **Answer**: "Subnet isolation enforces defense-in-depth. By placing RDS in its own DB subnets, we can apply strict network routing. The DB subnets have no route to the NAT Gateway, preventing database servers from initiating connections to the internet. This mitigates exfiltration risks if a web server is compromised."

### Q2: What happens to the running application if one Availability Zone goes completely dark?
*   **Answer**: "The architecture handles this automatically. The ALB continues routing to the node in the healthy AZ. The Auto Scaling Group detects that instances in the failed AZ are dead, terminates them, and spins up new instances in the surviving AZ. Meanwhile, RDS Multi-AZ performs a CNAME flip, promoting the standby database in the healthy AZ to primary."

### Q3: How do you access the EC2 instances for troubleshooting since there is no SSH key and port 22 is closed?
*   **Answer**: "We use AWS Systems Manager Session Manager. The launch template attaches an IAM instance profile with the `AmazonSSMManagedInstanceCore` policy. The SSM Agent on the instance connects outbound to the SSM endpoint. Admins log in using their IAM credentials, bypassing the need for open incoming ports, bastion hosts, or managing SSH keys."

### Q4: What is the security risk of storing database passwords in your `variables.tf` or `terraform.tfvars` files?
*   **Answer**: "If variables are stored in plain text, they can be committed to source control by accident. Additionally, Terraform stores variables in the `terraform.tfstate` file in plain text. To mitigate this in production, we should store credentials in AWS Secrets Manager and reference them dynamically."

### Q5: How does the ALB handle SSL/TLS termination, and why is this beneficial?
*   **Answer**: "The ALB decrypts HTTPS requests using a TLS certificate from AWS ACM before forwarding the plain text HTTP requests to the EC2 instances. This offloads the encryption CPU overhead from the web servers, simplifies certificate management, and allows central certificate rotation."

### Q6: If an EC2 instance is terminated by the ASG, what happens to its local log files?
*   **Answer**: "Local log files are lost when the instance is terminated because EBS volumes are ephemeral in this ASG setup. To prevent data loss, the EC2 user data installs the CloudWatch Agent, which streams system logs and Apache access logs continuously to a centralized CloudWatch Log Group."

### Q7: Why did you set `map_public_ip_on_launch = true` on the public subnets but not on the private ones?
*   **Answer**: "Public subnets need public IP addresses so that the Application Load Balancer nodes and NAT Gateways can communicate directly with the internet. Private subnets contain instances that should only communicate internally, so they do not require public IP addresses."

### Q8: What is the difference between Security Groups and Network ACLs (NACLs)?
*   **Answer**: "Security Groups are stateful firewalls operating at the instance level (ENI). If ingress is allowed, return egress is automatically permitted. NACLs are stateless firewalls operating at the subnet boundary, requiring explicit inbound and outbound rules. In this project, we rely on security groups for granular control."

### Q9: Why did you use `gp3` EBS volumes instead of `gp2` in your launch template?
*   **Answer**: "`gp3` volumes are more cost-effective than `gp2`. They provide a baseline performance of 3,000 IOPS and 125 MB/s throughput regardless of storage size, whereas `gp2` performance scales with size. `gp3` is roughly 20% cheaper per GB than `gp2`."

### Q10: How do you protect the S3 assets bucket from unauthorized public access?
*   **Answer**: "By default, S3 blocks all public access. We also attached a bucket policy that denies any request not using HTTPS secure transport (`aws:SecureTransport = false`). In production, we would also enforce S3 Block Public Access at the bucket and account levels."

### Q11: What would happen if you configured only one NAT Gateway for both Availability Zones?
*   **Answer**: "While it reduces costs, it creates a single point of failure. If the AZ containing the single NAT Gateway goes offline, the EC2 instances in the other AZ lose outbound internet connectivity. They cannot run updates, fetch packages, or call external APIs."

### Q12: Why did you use a Launch Template instead of a Launch Configuration?
*   **Answer**: "Launch Configurations are deprecated by AWS. Launch Templates support newer features, such as multiple versions, launch template inheritance, EC2 Spot instances, T3 Unlimited configurations, and metadata options (IMDSv2)."

### Q13: How does RDS Multi-AZ replication differ from RDS Read Replicas?
*   **Answer**: "Multi-AZ replication is synchronous, writing data to both the primary and standby databases before committing, ensuring zero data loss for high availability. Read Replica replication is asynchronous, designed for scaling read operations, and may experience replication lag."

### Q14: How would you protect the RDS database from accidental deletion by a developer or Terraform script?
*   **Answer**: "We would enable `deletion_protection = true` on the `aws_db_instance` resource. When enabled, AWS blocks delete requests until deletion protection is explicitly disabled via console or CLI. In this portfolio, we set it to false but documented it as a production requirement."

### Q15: What is the purpose of the `instance_refresh` block in the Auto Scaling Group?
*   **Answer**: "It automates rolling deployments when the Launch Template changes. When we update the AMI or user data, the instance refresh terminates a portion of the old instances, launches new ones, waits for health checks to pass, and continues until all instances are updated, ensuring zero downtime."
