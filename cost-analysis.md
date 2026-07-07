# Cost Analysis & Optimization

This document breaks down the cost drivers of the `secure-multi-tier-webapp` project. It provides estimates for running the infrastructure, outlines a low-cost "Lab Mode" configuration for educational testing, and offers design alternatives to avoid expensive AWS resources.

---

## 1. Main Cost Drivers (Production Environment)

If deployed exactly as specified in the default HCL configurations (across two AZs for High Availability), the monthly cost breakdown is approximately:

| Service | Configuration Details | Quantity | Monthly Cost (Est.) |
| :--- | :--- | :--- | :--- |
| **NAT Gateway** | $0.045/hour (running costs) + $0.045/GB data processed | 2 | ~$65.70 (idle) |
| **Application Load Balancer** | $0.0225/hour + $0.008/LCU-hour | 1 | ~$16.40 (idle) |
| **Amazon RDS MySQL** | `db.t3.micro` Multi-AZ, 20GB gp3 storage | 1 | ~$28.40 |
| **Amazon EC2 instances** | `t3.micro` (running 24/7) | 2 | ~$15.20 |
| **Amazon Elastic IPs (EIP)** | $0.005/hour (if unused, but free when attached) | 2 | $0.00 (attached) |
| **Amazon EBS Storage** | 20GB gp3 per instance | 2 | ~$3.20 |
| **S3, CloudWatch, Route 53** | Minimal log storage, alarms, and routing | - | <$2.00 |
| **Total Monthly Cost** | | | **~$130.90** |

*Note: Prices are estimates based on standard `us-east-1` region pricing. The biggest cost driver by far is the NAT Gateway tier.*

---

## 2. Low-Cost "Lab Mode" Recommendations

To validate this infrastructure in a live AWS account for under **$1.00**, modify the Terraform configuration before running `terraform apply` using the following recommendations:

1.  **Reduce NAT Gateways to One**:
    *   *Change*: In `main.tf`, change the NAT Gateway count from `2` to `1`. Make all private subnets route through this single NAT Gateway.
    *   *Savings*: Cuts NAT Gateway costs in half.
2.  **Disable Multi-AZ RDS**:
    *   *Change*: In `main.tf`, set `multi_az = false` on the `aws_db_instance` resource.
    *   *Savings*: Reduces database compute and storage costs by 50%.
3.  **Adjust Auto Scaling Group Size**:
    *   *Change*: In `main.tf`, update `aws_autoscaling_group.web` capacity values to `min_size = 1`, `max_size = 1`, and `desired_capacity = 1`.
    *   *Savings*: Eliminates the second EC2 instance and EBS volume.
4.  **Tear Down Immediately**:
    *   Never leave the stack running overnight. Deploy, verify target connectivity, and immediately execute `terraform destroy`. A 30-minute run will cost roughly **$0.15**.

---

## 3. Production Cost Considerations

*   **Savings Plans / Reserved Instances**: For production systems running continuously, purchase 1-year or 3-year Compute Savings Plans to save up to 72% on EC2 instance costs.
*   **RDS Reserved Instances**: Purchase RDS DB Instance Reservations to significantly reduce the Multi-AZ database hourly rate.
*   **Data Transfer Fees**: AWS charges for data transferred out to the internet, and data transferred between Availability Zones ($0.01 per GB). To minimize cross-AZ costs, ensure your application code accesses local AZ resources where possible.

---

## 4. NAT Gateway Alternative: NAT Instance

NAT Gateways are AWS-managed, highly available, and scale up to 100 Gbps, but their hourly charge is a major cost driver for small environments.

### The Low-Cost Alternative: NAT Instance
You can deploy a single, small EC2 instance running a NAT AMI (e.g., standard Amazon Linux configured with iptables IP masquerading) in a public subnet.

*   **Cost Comparison**: A `t3.nano` NAT instance costs ~$3.80/month, compared to $32.85/month for one NAT Gateway (a savings of **88%**).
*   **Infrastructure Diagram Change**:
    ```
    Private App Subnet ──► [Route: 0.0.0.0/0 via ENI] ──► [Public NAT Instance] ──► Internet Gateway
    ```
*   **Terraform Code Configuration**:
    ```terraform
    # Public NAT Instance
    resource "aws_instance" "nat" {
      ami                         = "ami-0c7217cdde317cfec" # Standard AMI
      instance_type               = "t3.nano"
      subnet_id                   = aws_subnet.public[0].id
      source_dest_check           = false # CRITICAL: Allows instance to route traffic
      
      user_data = <<-EOF
                  #!/bin/bash
                  sysctl -w net.ipv4.ip_forward=1
                  iptables -t nat -A POSTROUTING -o xnvd0 -j MASQUERADE
                  EOF
    }
    ```
*   **Trade-off Summary**: NAT instances are not managed by AWS. You are responsible for configuring OS updates, scaling bandwidth, and handling failover. If the NAT instance fails, all private subnet egress is cut off. NAT Gateways are recommended for production; NAT instances are ideal for non-critical development workloads.

---

## 5. Destroy Checklist (Resource Leak Prevention)

When tearing down your environment, ensure no resources are orphaned. Run `terraform destroy` and verify the following are removed:

- [ ] **NAT Gateways**: Confirm `aws_nat_gateway` instances are fully deleted (check the VPC console).
- [ ] **Elastic IPs (EIP)**: Verify EIPs allocated for the NAT Gateways are released. AWS charges $0.005/hour for unassociated EIPs.
- [ ] **Application Load Balancer**: Confirm the load balancer and target groups are destroyed to stop hourly billing.
- [ ] **RDS Databases**: Ensure the RDS instance is terminated and no final manual snapshots are kept unless explicitly needed (manual snapshots incur S3 storage fees).
- [ ] **EBS Volumes**: Verify EBS volumes attached to the ASG instances are deleted. (Configured in our template via `delete_on_termination = true`).
