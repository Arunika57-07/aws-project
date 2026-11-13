# AWS Internship Project: Documentation and Runbook

**Project:** Custom VPC + EC2 Web Application + S3 Storage + IAM Roles + CloudWatch Monitoring + Automated Backup and Cost Control
**Region:** ap-south-1 (Mumbai) | **OS:** Ubuntu 22.04 LTS | **Web server:** Apache2 | **Instance:** t3.micro (verify Free Tier eligibility in Billing before launch)
**Tags on every resource:** `Project=InternshipAWS`, `Env=Demo`, `Owner=<yourname>`

> Fill in `<yourname>`, your bucket name (S3 names are global, e.g. `internship-<yourname>-<random>`), and your email wherever they appear.

---

## 1. Architecture

```
 [ Intern IAM User ]  (MFA enabled, no root use)
          |
          v
 [ VPC 10.0.0.0/16 ] -- [ Internet Gateway ]
          |
 [ Public Subnet 10.0.1.0/24 ]  (route 0.0.0.0/0 -> IGW)
          |
 [ EC2 t3.micro: Ubuntu + Apache ]---[ Security Group: 22 from my IP, 80 open ]
      |            |
      |            +--> [ CloudWatch: CPU + StatusCheck alarms ] --> [ SNS topic ] --> email
      |
      +-- IAM instance role --> [ S3 bucket: assets/, data/, logs/yyyy-mm-dd/ ]
      |
      +-- root EBS volume --> [ One EBS snapshot (backup) ]

 [ AWS Budgets ] --> email at $1 and $3
```

---

## 2. Phase-by-phase runbook

### Phase 1: Account and IAM foundation
1. Sign in as root once. Enable MFA: **Account name > Security credentials > Assign MFA device**.
2. **IAM > Users > Create user** `intern-<yourname>` with console access. Do not use root afterwards.
3. **IAM > User groups**: create `InternDevelopers` and `CloudOperators`. Add your user to `InternDevelopers`.
4. **IAM > Policies > Create policy > JSON**: paste `iam/intern-developers-policy.json` (replace `REPLACE-BUCKET-NAME`), name it `InternDevelopersPolicy`, and attach it to the group.
5. **IAM > Roles > Create role**: trusted entity AWS service, EC2 (matches `iam/ec2-trust-policy.json`). Create the policy from `iam/ec2-s3-role-policy.json` (name `InternshipS3Access`), attach it, and name the role `InternshipEC2Role`. EC2 will wrap it in an instance profile automatically.
6. Also attach the AWS managed policy `CloudWatchAgentServerPolicy` to the role if you plan to ship logs to CloudWatch Logs.

**Why instance roles beat access keys:** the role issues temporary credentials that rotate automatically, nothing is stored on disk or in code, nothing can leak through a Git commit or an AMI, and permissions are revoked instantly by editing the role.

### Phase 2: Networking
Either use the console (**VPC > Create VPC > VPC and more** is the fastest, set 1 AZ, 1 public subnet, 0 private subnets, **NAT gateways: None**, VPC endpoints: None) or run:

```bash
./scripts/create-network.sh <yourname>
```

Verify: subnet auto-assign public IPv4 is on, and the route table has `0.0.0.0/0 -> igw-...`. Security group rules: SSH 22 from **your IP/32 only**, HTTP 80 from anywhere.

### Phase 3: Compute and application
1. **EC2 > Launch instance**: Ubuntu 22.04, t3.micro, create key pair `internship-key.pem`, select your VPC/subnet, the security group, storage 8 GiB gp3, IAM instance profile `InternshipEC2Role`. Paste `scripts/user-data.sh` into **Advanced > User data**.
2. Connect:
   ```bash
   chmod 400 internship-key.pem
   ssh -i internship-key.pem ubuntu@<EC2-PUBLIC-IP>
   ```
3. Check Apache: `curl http://127.0.0.1` and `curl http://127.0.0.1/health`, then open `http://<EC2-PUBLIC-IP>` in a browser.
4. Generate traffic for logs: `for i in $(seq 1 50); do curl -s http://<EC2-PUBLIC-IP>/ >/dev/null; curl -s http://<EC2-PUBLIC-IP>/nope >/dev/null; done`

### Phase 4: Storage (S3 and EBS snapshot)
```bash
# From your laptop (IAM user credentials via `aws configure`)
aws s3 mb s3://<bucket> --region ap-south-1
aws s3api put-public-access-block --bucket <bucket> \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3 cp webapp/index.html s3://<bucket>/assets/
aws s3 cp webapp/assets/style.css s3://<bucket>/assets/
aws s3 cp data/web-access-logs.csv s3://<bucket>/data/

# On the EC2 instance (uses the role, no keys)
aws s3 sync s3://<bucket>/assets/ /var/www/html/
sudo ./scripts/sync-logs.sh <bucket>
```
Snapshot (console: **EC2 > Volumes > select root volume > Actions > Create snapshot**) or:
```bash
aws ec2 create-snapshot --volume-id <vol-id> --description "InternshipAWS demo backup" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Project,Value=InternshipAWS},{Key=Env,Value=Demo}]'
```

**Restore plan:**
1. EC2 > Snapshots > select the snapshot > **Create volume from snapshot** in the same AZ.
2. Stop the instance, detach the damaged root volume, attach the restored volume as `/dev/sda1`, start the instance. (Or **Create image from snapshot** and launch a new instance from the AMI.)
3. SSH in, run `curl http://127.0.0.1/health` to confirm Apache is back.
4. Delete the unused volume afterwards to avoid storage charges.

### Phase 5: Monitoring, alerts, cost control
1. **SNS > Topics > Create topic** (Standard) `internship-alerts`. Create an email subscription and **click the confirmation link in your inbox**.
2. **CloudWatch > Alarms > Create alarm**:
   - `EC2 > Per-Instance Metrics > CPUUtilization`, statistic Average, period 5 minutes, threshold > 70, notify `internship-alerts`.
   - `StatusCheckFailed` >= 1, period 1 minute, same topic.
3. Optional logs: install the CloudWatch agent and ship only `/var/log/apache2/access.log`, with log group retention set to 3 days.
4. **Billing > Budgets > Create budget**: Cost budget, monthly, $3; alerts at actual $1 and $3 (as percentages of $3: 33% and 100%) to your email. Also enable Free Tier usage alerts in Billing preferences.
5. Simulate load: `sudo ./scripts/cpu-stress.sh`, watch the alarm go **In alarm** and the email arrive, then confirm the load stopped.

### Phase 6: Log analysis and validation
```bash
python3 scripts/analyze_logs.py data/web-access-logs.csv
```
Sample output is in `docs/analysis-output.txt`.

**IAM denial test** (from the instance, should fail):
```bash
aws s3 ls s3://some-other-bucket          # expect AccessDenied
aws s3 ls s3://<bucket>                   # expect success
aws ec2 describe-instances                # expect UnauthorizedOperation (role has no EC2 rights)
```
Screenshot the AccessDenied errors as evidence.

---

## 3. Analysis results (sample dataset)

`data/web-access-logs.csv` holds 600 synthetic requests (3 days, 60 unique IPs from the 203.0.113.0/24 documentation range).

| Question | Result |
|---|---|
| Total requests | 600 |
| Unique visitor IPs | 60 |
| Top requested page | `/index.html` (185), then `/health` (95), `/projects.html` (82) |
| 4xx errors | 33 (5.5%), mostly 404 on a missing page plus 401/403 on `/admin` |
| 5xx errors | 10 (1.7%) |
| Peak traffic hour | 10:00 to 10:59 (98 requests) |

Interpretation: `/health` traffic shows uptime checks, the 401/403 hits on `/admin` suggest probing worth watching, and the 5xx rate is low but would justify a log-based alarm in production.

---

## 4. Free Tier safety checklist

- [ ] Only one micro EC2 instance running
- [ ] No NAT Gateway, ALB or RDS created
- [ ] S3 holds only small demo files and logs
- [ ] CloudWatch log retention set to 3 days, ingestion minimal
- [ ] One snapshot only
- [ ] Budget alert set and email confirmed
- [ ] All resources tagged
- [ ] Unused resources stopped or terminated after the demo (`scripts/cleanup.sh`)
- [ ] Billing dashboard checked twice a week

## 5. Risks and mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| Unexpected AWS charges | High | Free Tier services only, Budgets, no NAT/ALB/RDS |
| SSH open to the world | High | Port 22 limited to your IP/32 (update it if your IP changes) |
| Over-permissioned IAM | Medium | Bucket-scoped policies, instance role, no access keys |
| Too many logs in CloudWatch | Medium | Short retention, one log file |
| Forgotten resources | Medium | Tags plus cleanup script |

## 6. Four-week plan

- **Week 1:** IAM, VPC plan, diagram, dataset
- **Week 2:** EC2, web app, security group, S3 integration
- **Week 3:** CloudWatch, SNS, snapshot, budget, log analysis
- **Week 4:** End-to-end test, screenshots, documentation, video

## 7. Screenshot checklist (deliverables)

1. IAM user, groups, role and policies (hide account ID if you like)
2. VPC, subnet, route table and IGW
3. Browser and `curl` showing the site
4. S3 bucket structure and object list
5. Dataset plus analysis output
6. CloudWatch alarm and SNS email
7. Snapshot page
8. Budget alert
9. IAM AccessDenied test
10. Filled safety checklist

## 8. Video script (5 to 10 minutes)

1. **0:00** Intro: goal and why Free Tier-safe design matters
2. **1:00** IAM: user, groups, instance role, why no access keys
3. **2:30** VPC: subnet, IGW, route table, security group
4. **4:00** EC2 and website demo in browser and curl
5. **5:30** S3 sync and log archive using the role, then the AccessDenied test
6. **7:00** CloudWatch alarm firing from the stress test, SNS email
7. **8:00** Snapshot and restore plan, Budget alert
8. **9:00** Log analysis results, cleanup, lessons learned
