# Operations Runbook

This runbook contains standard operating procedures (SOPs) for monitoring, scaling, backup recovery, and incident response for the secure multi-tier web application.

---

## 1. Health Checks Overview

The architecture relies on layered health checks to monitor the system's operational status:

*   **EC2 Instance Status Checks**: AWS performs hypervisor and hardware checks. Failed checks trigger automatic replacement if configured via CloudWatch actions.
*   **ALB Target Group Health Checks**: 
    *   *Path*: `/`
    *   *Protocol*: HTTP (Port 80)
    *   *Mechanism*: The ALB queries the target EC2 nodes every 30 seconds. If an instance fails to return a `200 OK` three consecutive times, it is marked as `Unhealthy` and removed from the active routing pool.
*   **ASG Health Checks**: The Auto Scaling Group evaluates the ALB Target Group status. If an instance is marked `Unhealthy` by the ALB, the ASG automatically terminates the node and launches a new one in the private subnet.

---

## 2. Alarm Response Playbooks

### Alarm: `asg-high-cpu` (Average CPU >= 80% for 10 minutes)
1.  **Acknowledge**: Set the alarm state to "In Progress" in the CloudWatch console.
2.  **Verify Scaling**: Check if the Auto Scaling Group has already launched replacement instances (confirm capacity limits in the EC2 Auto Scaling console).
3.  **Investigate logs**:
    *   Access the target instances via SSM Session Manager.
    *   Check CPU consumer processes using `top` or `htop`.
    *   Examine Apache logs (`/var/log/httpd/access_log`) for spikes in request traffic or malicious requests (e.g., DDOS attempts).
4.  **Remediation**: If scaling is blocked by the configured `max_size = 4` limit, temporarily increase the limit to accommodate the traffic burst, then optimize the application.

### Alarm: `rds-low-storage` (Free space < 5 GB)
1.  **Assess urgency**: RDS instance storage is set to 20 GB. Dropping below 5 GB requires prompt attention to prevent database locks.
2.  **Remediation (Auto-Scaling)**: If RDS Storage Auto-scaling is enabled, verify it is provisioning additional storage.
3.  **Manual Expansion**:
    *   Go to the RDS console, select the DB instance, and click **Modify**.
    *   Increase the **Allocated Storage** value (e.g. increase from 20 GB to 40 GB).
    *   *Note*: Modifying storage size does not cause database downtime, but you must wait at least 6 hours between storage modifications.

---

## 3. Scaling Response & Capacity Management

*   **Dynamic Scaling**: The target tracking policy maintains CPU at 70%. Ensure your applications are stateless so instances can be terminated without data loss.
*   **Manual Scaling Override**:
    *   To scale out during an expected marketing event, adjust the ASG capacity via the CLI:
      ```bash
      aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name secure-multi-tier-dev-asg \
        --min-size 4 --desired-capacity 4 --max-size 8
      ```

---

## 4. RDS Backup & Restore Procedures

### Automated Backups
RDS automatically backs up the database daily during the backup window (`03:00-04:00 UTC`) and retains snapshots for 7 days.

### Performing a Point-in-Time Restore (PITR)
If data corruption occurs:
1.  Go to the **RDS Console** and select the database instance.
2.  Click **Actions** -> **Restore to Point in Time**.
3.  Select the restore time (up to 5 minutes prior to the current time).
4.  Specify a new database identifier (e.g., `secure-multi-tier-dev-mysql-restored`).
5.  Set database subnet groups and security groups to match the primary instance.
6.  Once restored, update your application's DB host endpoint variable in Parameter Store or Secrets Manager, then perform a rolling instance refresh to pick up the new connection endpoint.

---

## 5. Deployment Rollback Strategy

We utilize an ASG **Instance Refresh** to implement rolling deployments. If a deployment contains errors:

1.  **Cancel Refresh**: If a deployment is currently in progress, cancel the active instance refresh immediately via the AWS CLI or Console:
    ```bash
    aws autoscaling cancel-instance-refresh \
      --auto-scaling-group-name secure-multi-tier-dev-asg
    ```
2.  **Roll back Launch Template**: Revert the Launch Template default version to the previous stable release.
3.  **Trigger New Refresh**: Start a new Instance Refresh to roll back the running servers to the previous version:
    ```bash
    aws autoscaling start-instance-refresh \
      --auto-scaling-group-name secure-multi-tier-dev-asg
    ```

---

## 6. Incident Response Checklist

During an active outage, follow this checklist:

*   [ ] **Identify Impact**: Check CloudWatch dashboards to see if the issue is affecting all zones or a single AZ. Check ALB target response metrics (5XX errors vs 4XX errors).
*   [ ] **Validate Networking**: Ensure NAT Gateways are active and have not exhausted their IP connections. Verify Route 53 is resolving correctly.
*   [ ] **Check Database Status**: Confirm RDS CPU, memory, and database connections. Verify if a failover occurred (check RDS event log).
*   [ ] **Examine Log Streams**: Look at CloudWatch Logs under `/aws/ec2/secure-multi-tier-dev-app-logs` to review stack traces.
*   [ ] **Mitigate**: If a bad release is suspected, execute the **Deployment Rollback** procedure. If an instance is hung, terminate it manually to force the ASG to recreate it.
