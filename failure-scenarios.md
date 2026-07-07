# Failure Scenarios & Mitigation Playbooks

This document analyzes potential system failures within the secure multi-tier web application architecture, explaining the impact of each failure and providing step-by-step mitigation procedures.

---

## 1. Availability Zone (AZ) Failure

### Scenario
An entire AWS Availability Zone (e.g., `us-east-1a`) experiences a catastrophic outage due to physical utility failure.

### Impact
*   ALB loses its node in the affected AZ.
*   50% of the EC2 web servers in the ASG terminate.
*   If the primary RDS instance was in the affected AZ, the database connection drops temporarily.

### Recovery/Mitigation
*   **ALB**: Completely automated. Route 53 routes 100% of traffic to the surviving ALB node in `us-east-1b`.
*   **RDS Failover**: Synchronous Multi-AZ configuration automatically triggers. The standby RDS database in the surviving AZ promotes itself to primary, updating the DNS CNAME under the hood. The application reconnects automatically (typically within 30-60 seconds).
*   **Compute Auto-Healing**: The ASG detects that the capacity in the affected AZ has dropped. It provisions replacement instances in the surviving AZ (shifting the running count back to the desired capacity of `2`).

---

## 2. Single EC2 Instance Failure

### Scenario
An EC2 web server crashes due to an out-of-memory (OOM) error or OS kernel panic.

### Impact
*   The affected server stops responding to web requests.
*   ALB continues routing traffic to it briefly, leading to localized 502/504 errors.

### Recovery/Mitigation
1.  **ALB Health Checks**: Within 90 seconds (3 checks * 30-second interval), the ALB marks the instance as `Unhealthy`.
2.  **Traffic Rerouting**: The ALB stops forwarding requests to the failed instance, sending them to the surviving instances instead.
3.  **ASG Re-creation**: The ASG detects the unhealthy status from the load balancer, terminates the failed instance, and provisions a new one from the launch template.

---

## 3. Database (RDS) Failure

### Scenario
The primary database engine crashes or experiences hardware failure.

### Impact
*   All active database connections are severed.
*   Web servers display error pages (e.g., 500 Internal Server Error) due to failed DB connections.

### Recovery/Mitigation
*   **Automatic Multi-AZ Promotion**: AWS RDS detects the failure and initiates a failover.
*   **Client Reconnection**: Ensure your application database connection pool has retry logic configured. When the DNS record is updated (within ~60 seconds), client queries will automatically succeed on the newly promoted master.
*   *Note*: If database failover hangs, manually trigger a reboot with failover via the CLI:
    ```bash
    aws rds reboot-db-instance \
      --db-instance-identifier secure-multi-tier-dev-mysql \
      --force-failover
    ```

---

## 4. ALB Health Check Failure

### Scenario
All EC2 instances are marked as `Unhealthy` by the ALB target group, even though they appear to be running.

### Impact
*   The ALB returns a `503 Service Temporarily Unavailable` to users.
*   The ASG starts a cascade of instance terminations, replacing instances in a loop.

### Recovery/Mitigation
1.  **Suspend ASG Processes**: Temporarily suspend the ASG's termination process to prevent it from killing debugging nodes:
    ```bash
    aws autoscaling suspend-processes \
      --auto-scaling-group-name secure-multi-tier-dev-asg \
      --scaling-processes HealthCheck ReplaceUnhealthy
    ```
2.  **Investigate Targets**: Connect to a running instance via Systems Manager Session Manager.
3.  **Check Services**: Verify that the Apache service is listening on port 80 (`netstat -tulnp`).
4.  **Validate Health Endpoint**: Query the local endpoint (`curl -I http://localhost:80/`) to check the response code.
5.  **Examine Security Groups**: Verify that the EC2 security group allows ingress from the ALB security group.

---

## 5. NAT Gateway Failure

### Scenario
An AWS-side NAT Gateway issue occurs or the NAT Gateway is deleted.

### Impact
*   EC2 instances in private subnets cannot connect to the internet.
*   Updates, patches, or external API queries fail.
*   Health checks that require outbound connectivity (e.g. database setup scripts downloading dependencies) will hang.

### Recovery/Mitigation
*   **Validate Routes**: Check the routing tables for the private subnets. Ensure the route for `0.0.0.0/0` points to a valid NAT Gateway ID.
*   **Re-create NAT GW**: If the NAT Gateway was deleted, provision a new NAT Gateway in a public subnet, allocate a new EIP, and update the private route table to point to the new gateway ID.

---

## 6. Security Group Misconfiguration

### Scenario
An engineer accidentally removes the database ingress rule, or changes the port settings.

### Impact
*   Compute nodes cannot reach RDS.
*   Application logs display connection timeout errors: `Connection timed out (110)`.

### Recovery/Mitigation
1.  **Run Reachability Analyzer**: Use VPC Reachability Analyzer in the AWS Console to trace paths between the EC2 instances and the RDS instance network interfaces.
2.  **Verify DB Security Group Rules**: Confirm there is a rule permitting port `3306` from the source Security Group of the EC2 instances (`aws_security_group.web.id`). Do **not** use IP-based rules for dynamic EC2 nodes; always reference security group IDs.

---

## 7. Cost Spike Scenario

### Scenario
The monthly AWS bill shows a massive, unexpected increase.

### Impact
*   Budget threshold alarms trigger.
*   Increased business operational costs.

### Recovery/Mitigation
1.  **Examine Cost Explorer**: Filter costs by service and resource tags.
2.  **Check NAT Gateway Data Processing**: High data processing fees indicate that application servers are downloading huge datasets or transferring uncompressed files over the internet.
    *   *Solution*: Set up VPC Endpoints (PrivateLink) for S3 and DynamoDB to route internal traffic over the AWS backbone for free, bypassing the NAT Gateways.
3.  **Identify Orphaned Resources**: Check for unused EIPs, orphaned EBS volumes from manually deleted instances, and RDS snapshots that are no longer required.
