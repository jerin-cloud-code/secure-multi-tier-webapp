# Architecture Design Document

This document provides a deep architectural breakdown of the `secure-multi-tier-webapp` project, detailing the design patterns, traffic flows, security borders, and alignment with the AWS Well-Architected Framework.

---

## 1. Request Flow (End-to-End)

When a client accesses the web application, the network request follows a strict path from the public internet down to the private database:

1.  **DNS Lookup**: The client queries Route 53 (using the configured domain name `portfolio.example.com`). Route 53 resolves the domain to the public-facing CNAME of the Application Load Balancer (ALB).
2.  **Public Ingress**: The client initiates an HTTPS/HTTP connection. The request arrives at the Internet Gateway (IGW) and is routed to one of the public subnets containing the ALB nodes (distributed across AZ-A and AZ-B for high availability).
3.  **ALB Evaluation**: The ALB terminates the request, evaluates any listener rules, and validates the target health. The ALB security group permits incoming traffic on ports 80/443 from `0.0.0.0/0`.
4.  **Forwarding to App Tier**: The ALB forwards the HTTP request to the Auto Scaling Group (ASG) web instances in the private app subnets. The ALB routes traffic across AZ-A and AZ-B.
5.  **Compute Ingress**: The EC2 instances process the web request. Importantly, these EC2 instances lack public IP addresses and sit behind a security group that **only** allows ingress on port 80 if the request originates from the ALB's security group.
6.  **Database Query**: The application queries the RDS MySQL Database. The request is routed internally to the primary RDS instance in the private database subnet.
7.  **Database Ingress**: The database security group blocks all incoming traffic except for MySQL queries (port 3306) originating from the EC2 web server security group.
8.  **Outbound Path (Updates/Patching)**: If an EC2 instance needs to pull security updates or download packages, the traffic is routed to the NAT Gateway in the public subnet, which acts as a proxy to the public internet, masking the private IP of the instance.

---

## 2. High Availability & Resiliency Design

The architecture is designed to handle availability zone (AZ) failures with zero manual intervention:

*   **Multi-AZ Subnets**: Every logical tier (ALB, Compute, Database) spans two distinct AWS Availability Zones.
*   **ALB Redundancy**: The ALB is configured as a public load balancer across two public subnets. AWS automatically provisions load balancer nodes in both AZs, managing scaling and failover under the hood.
*   **Auto Scaling Group (ASG)**: The ASG is mapped to the two private app subnets. If an entire AZ becomes unavailable, the ASG detects instance health failures and automatically spins up replacement instances in the surviving AZ.
*   **Multi-AZ RDS**: The RDS database is configured with `multi_az = true`. AWS provisions a primary database instance in AZ-A and a synchronous standby replica in AZ-B. In the event of primary database failure or AZ outage, AWS automatically performs a CNAME flip to promote the standby instance to primary, resulting in minimal downtime (typically under 60 seconds) without application code changes.
*   **NAT Gateway Redundancy**: Separate NAT Gateways are provisioned in each public subnet. If AZ-A experiences a total outage, instances in AZ-B will continue to route outbound traffic through NAT-B, avoiding a single point of failure at the network gateway layer.

---

## 3. Security Boundary Isolation

The architecture uses a defense-in-depth approach utilizing AWS security boundaries:

```
[Internet]
    │
==================== PUBLIC BOUNDARY ====================
    │  (Ingress: 80/443 from 0.0.0.0/0)
    ▼
[Application Load Balancer] (Public Subnets)
    │
==================== PRIVATE APP BOUNDARY =================
    │  (Ingress: 80 only from ALB Security Group)
    ▼
[Auto Scaling EC2 Tier] (Private App Subnets)
    │
==================== PRIVATE DB BOUNDARY =================
    │  (Ingress: 3306 only from EC2 Security Group)
    ▼
[RDS Multi-AZ MySQL] (Private DB Subnets)
```

1.  **VPC Isolation**: The custom VPC provides a logical boundary. Inside the VPC, subnets segment resources based on access requirements.
2.  **No Public IPs on Compute/DB**: EC2 instances and RDS instances are placed in private subnets with RFC 1918 private IP addresses. They cannot be targeted directly from the internet.
3.  **Strict Security Group Rules**: Statefully filters traffic between boundaries. The database security group does not trust the load balancer directly; it only trusts the compute layer.
4.  **SSM Systems Manager (No SSH)**: The launch template does not include an SSH key pair, and the EC2 security group blocks port 22. Instead, instances use an IAM role with `AmazonSSMManagedInstanceCore` to allow administrators to access the shell securely via AWS Systems Manager Session Manager, auditing all terminal sessions.

---

## 4. Scaling Approach

Scaling is handled automatically based on application load:

*   **Target Tracking Scaling Policy**: The ASG uses a target tracking scaling policy based on the average CPU utilization (`ASGAverageCPUUtilization`).
*   **Target Metric**: The threshold is set to `70%`. If average CPU utilization exceeds this value, the ASG automatically launches additional EC2 instances. If CPU utilization falls, it terminates unneeded instances.
*   **Instance Refresh**: Outlines a rolling deployment strategy. Updates to the Launch Template trigger an ASG Instance Refresh, replacing instances gradually to maintain a minimum of 50% healthy capacity during deployments.

---

## 5. AWS Well-Architected Review

The table below outlines how this design addresses the pillars of the AWS Well-Architected Framework:

| Pillar | Architectural Principle | Implementation Details in This Project |
| :--- | :--- | :--- |
| **Operational Excellence** | Perform operations as code | Defined using modular Terraform templates. Operations can be checked, versioned, and rolled back. |
| | Annotate documentation | Comprehensive runbooks, failure scenarios, and guides are written in markdown alongside code. |
| **Security** | Implement a strong identity foundation | EC2 instances use IAM roles and instance profiles. No AWS credentials or DB secrets are stored on the servers. |
| | Protect data in transit and at rest | S3 logs bucket enforces TLS and AES256 encryption. RDS volume uses AWS-managed KMS keys. ALB is configured to host TLS certificates. |
| | Apply security at all layers | Structured security groups isolate the Load Balancer, Web Server, and Database layers from each other. |
| **Reliability** | Test recovery procedures | Failure scenarios document explicit manual and automated recovery paths for AZ, instance, and RDS failovers. |
| | Scale horizontally | Computes are deployed in an Auto Scaling Group across 2 AZs, utilizing stateless application nodes. |
| **Performance Efficiency** | Democratize advanced technologies | Utilizes managed services like AWS ALB and RDS rather than self-hosting load balancers or database servers on EC2. |
| | Go global in minutes | The region variable enables spinning up this entire multi-AZ stack in any AWS region worldwide. |
| **Cost Optimization** | Measure overall efficiency | Compares production HA configuration with a low-cost "Lab Mode" to optimize compute and network costs. |
| | Eliminate unnecessary expense | Outlines a teardown check list to ensure all public IP allocations (EIPs), NAT GWs, and RDS instances are destroyed. |
| **Sustainability** | Maximize utilization | Auto Scaling ensures compute resources are dynamically provisioned based on demand, avoiding idle power consumption. |
| | Use managed services | Offloading operations to RDS and S3 optimizes hardware lifecycle efficiency under the AWS Shared Responsibility Model. |
