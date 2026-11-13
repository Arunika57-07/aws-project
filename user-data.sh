#!/bin/bash
# EC2 user-data: runs once at first boot (Ubuntu 22.04/24.04). Installs Apache and a health page.
set -e
apt-get update -y
apt-get install -y apache2 awscli unzip stress
systemctl enable --now apache2
mkdir -p /var/www/html/assets
echo "OK" > /var/www/html/health
cat > /var/www/html/index.html <<'EOF'
<h1>Student Portal - AWS Internship Demo</h1>
<p>Server is up. Replace this page by syncing from S3 (see runbook).</p>
EOF
