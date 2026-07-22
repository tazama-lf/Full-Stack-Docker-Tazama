# SPDX-License-Identifier: Apache-2.0
# deploy-tazama-sandbox.ps1
#
# Provisions the AWS infrastructure for the Tazama beta sandbox.
# Runs from your local Windows machine. Requires AWS CLI v2 configured with
# credentials that have EC2, IAM, and optionally Route53/ACM permissions.
#
# Usage:
#   .\deploy-tazama-sandbox.ps1 -AdminCidr "203.0.113.0/24"
#
# After this script completes:
#   1. Wait ~3 minutes for the bootstrap to finish on the instance.
#   2. Connect via SSM:  aws ssm start-session --target <instance-id> --region <region>
#   3. Set GH_TOKEN:     nano /opt/tazama/.env
#   4. Deploy the stack: /opt/tazama/AWS_deployment/deploy-tazama.sh

param(
    # Target AWS region
    [string]$Region        = "eu-west-1",

    # EC2 instance type. m5.2xlarge (8 vCPU / 32 GB) is the minimum for the full-service stack.
    # Step up to m5.4xlarge if you observe memory pressure via: docker stats
    [string]$InstanceType  = "m5.2xlarge",

    # AMI ID to use. If left blank, the script will look up the latest Amazon Linux 2023 AMI.
    [string]$AmiId         = "",

    # VPC ID to launch into. If left blank, uses the region's default VPC.
    [string]$VpcId         = "",

    # Name for the EC2 security group.
    [string]$SgName        = "tazama-sandbox-sg",

    # IAM role and instance profile names.
    [string]$RoleName      = "tazama-sandbox-ssm-role",
    [string]$ProfileName   = "tazama-sandbox-instance-profile",

    # Name tag applied to the EC2 instance.
    [string]$TagName       = "tazama-sandbox",

    # CIDR block allowed to access Hasura (6100) and pgAdmin (5050).
    # These expose raw database access so they must NOT be left open to 0.0.0.0/0.
    # Example: "203.0.113.0/24" for an office network, or "x.x.x.x/32" for a single IP.
    # If blank, those ports are not opened - you can add them manually later.
    [string]$AdminCidr     = ""
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 1. IAM role and instance profile for SSM (replaces SSH/port 22 entirely)
# ---------------------------------------------------------------------------
Write-Host "--- IAM Role and Instance Profile ---"

$roleExists = aws iam get-role `
    --role-name $RoleName `
    --query "Role.RoleName" `
    --output text 2>$null

if ($roleExists -ne $RoleName) {
    Write-Host "Creating IAM role: $RoleName"
    $trustPolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    $tmpTrust = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpTrust, $trustPolicy, [System.Text.Encoding]::UTF8)
    aws iam create-role `
        --role-name $RoleName `
        --assume-role-policy-document "file://$tmpTrust" | Out-Null
    Remove-Item $tmpTrust
    aws iam attach-role-policy `
        --role-name $RoleName `
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    Write-Host "IAM role created and AmazonSSMManagedInstanceCore policy attached."
} else {
    Write-Host "IAM role $RoleName already exists - skipping."
}

$profileExists = aws iam get-instance-profile `
    --instance-profile-name $ProfileName `
    --query "InstanceProfile.InstanceProfileName" `
    --output text 2>$null

if ($profileExists -ne $ProfileName) {
    Write-Host "Creating instance profile: $ProfileName"
    aws iam create-instance-profile --instance-profile-name $ProfileName | Out-Null
    aws iam add-role-to-instance-profile `
        --instance-profile-name $ProfileName `
        --role-name $RoleName
    Write-Host "Waiting 15 seconds for IAM propagation before launching instance..."
    Start-Sleep -Seconds 15
} else {
    Write-Host "Instance profile $ProfileName already exists - skipping."
}

# ---------------------------------------------------------------------------
# 2. Security group
#    Port 22 is intentionally absent. All management is via SSM Session Manager.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Security Group ---"

$sgId = aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=$SgName" `
    --region $Region `
    --query "SecurityGroups[0].GroupId" `
    --output text

if ($sgId -eq "None" -or -not $sgId) {
    Write-Host "Creating security group: $SgName"
    $createArgs = @(
        "ec2", "create-security-group",
        "--group-name", $SgName,
        "--description", "Tazama sandbox - user-facing ports only, no SSH",
        "--region", $Region,
        "--output", "text"
    )
    if ($VpcId) { $createArgs += @("--vpc-id", $VpcId) }
    $sgId = & aws @createArgs

    # User-facing ports (open to all beta users)
    aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 3001 --cidr 0.0.0.0/0 --region $Region | Out-Null
    Write-Host "  Opened port 3001 (Demo UI) to 0.0.0.0/0"
    aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 5000 --cidr 0.0.0.0/0 --region $Region | Out-Null
    Write-Host "  Opened port 5000 (TMS API) to 0.0.0.0/0"
    aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 5100 --cidr 0.0.0.0/0 --region $Region | Out-Null
    Write-Host "  Opened port 5100 (Admin Service API) to 0.0.0.0/0"
    aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 4000 --cidr 0.0.0.0/0 --region $Region | Out-Null
    Write-Host "  Opened port 4000 (NATS utilities) to 0.0.0.0/0"

    # Admin-only ports (Hasura + pgAdmin expose raw DB access)
    if ($AdminCidr) {
        aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 6100 --cidr $AdminCidr --region $Region | Out-Null
        Write-Host "  Opened port 6100 (Hasura) to $AdminCidr"
        aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 5050 --cidr $AdminCidr --region $Region | Out-Null
        Write-Host "  Opened port 5050 (pgAdmin) to $AdminCidr"
    } else {
        Write-Host ""
        Write-Host "  WARNING: -AdminCidr not provided."
        Write-Host "  Hasura (6100) and pgAdmin (5050) are NOT opened."
        Write-Host "  Add them manually once you know your admin IP/CIDR:"
        Write-Host "    aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 6100 --cidr <your-cidr> --region $Region"
        Write-Host "    aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 5050 --cidr <your-cidr> --region $Region"
    }
} else {
    Write-Host "Security group $SgName already exists ($sgId) - skipping."
}

# ---------------------------------------------------------------------------
# 3. AMI lookup (latest Amazon Linux 2023 x86_64)
# ---------------------------------------------------------------------------
if (-not $AmiId) {
    Write-Host ""
    Write-Host "--- AMI Lookup ---"
    $AmiId = aws ec2 describe-images `
        --owners amazon `
        --filters "Name=name,Values=al2023-ami-*-kernel-*-x86_64" "Name=state,Values=available" `
        --query "sort_by(Images, &CreationDate)[-1].ImageId" `
        --output text `
        --region $Region
    Write-Host "Using AMI: $AmiId"
}

# ---------------------------------------------------------------------------
# 4. User data - bootstrap script that runs automatically on first boot.
#    This installs Docker, clones the repo, and prepares the instance.
#    The GH_TOKEN placeholder must be replaced before running deploy-tazama.sh.
# ---------------------------------------------------------------------------
$userData = @'
#!/bin/bash
set -e

dnf update -y
dnf install -y git docker

# Install Docker Compose plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
     -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Clone the repo (main branch = latest stable release)
git clone https://github.com/tazama-lf/Full-Stack-Docker-Tazama -b main /opt/tazama

# Write .env with placeholder values.
# IMPORTANT: Update GH_TOKEN before running deploy-tazama.sh.
cat > /opt/tazama/.env <<'ENVEOF'
GH_TOKEN=REPLACE_ME
TAZAMA_VERSION=latest
TMS_PORT=5000
ADMIN_PORT=5100
PGADMIN_PORT=5050
ENVEOF

chmod +x /opt/tazama/AWS_deployment/deploy-tazama.sh
chmod +x /opt/tazama/AWS_deployment/reset-tazama.sh

chown -R ec2-user:ec2-user /opt/tazama

echo "Bootstrap complete." >> /var/log/tazama-bootstrap.log
echo "Connect via SSM, set GH_TOKEN in /opt/tazama/.env, then run /opt/tazama/AWS_deployment/deploy-tazama.sh" >> /var/log/tazama-bootstrap.log
'@

$userDataB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))

# ---------------------------------------------------------------------------
# 5. Launch EC2 instance
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Launching EC2 Instance ---"
Write-Host "Instance type: $InstanceType"
Write-Host "AMI:           $AmiId"

$instanceId = aws ec2 run-instances `
    --image-id $AmiId `
    --instance-type $InstanceType `
    --security-group-ids $sgId `
    --iam-instance-profile "Name=$ProfileName" `
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=100,VolumeType=gp3}" `
    --user-data $userDataB64 `
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TagName}]" `
    --region $Region `
    --query "Instances[0].InstanceId" `
    --output text

Write-Host "Instance launched: $instanceId"
Write-Host "Waiting for running state..."
aws ec2 wait instance-running --instance-ids $instanceId --region $Region
Write-Host "Instance is running."

# ---------------------------------------------------------------------------
# 6. Elastic IP
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Elastic IP ---"
$allocResult = aws ec2 allocate-address --domain vpc --region $Region | ConvertFrom-Json
$allocationId = $allocResult.AllocationId
$publicIp     = $allocResult.PublicIp

aws ec2 associate-address `
    --instance-id $instanceId `
    --allocation-id $allocationId `
    --region $Region | Out-Null

Write-Host "Elastic IP $publicIp allocated and associated."

# ---------------------------------------------------------------------------
# 7. Save state to file for use by teardown script
# ---------------------------------------------------------------------------
$state = [ordered]@{
    instanceId   = $instanceId
    allocationId = $allocationId
    publicIp     = $publicIp
    sgId         = $sgId
    region       = $Region
    roleName     = $RoleName
    profileName  = $ProfileName
    deployedAt   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
}
$stateFile = "$PSScriptRoot\sandbox-state.json"
$state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
Write-Host "State saved to $stateFile"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host "Sandbox provisioned successfully."
Write-Host ""
Write-Host "  Public IP:    $publicIp"
Write-Host "  Instance ID:  $instanceId"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Wait ~3 minutes for the bootstrap script to complete."
Write-Host "     Monitor progress: check /var/log/tazama-bootstrap.log via SSM."
Write-Host ""
Write-Host "  2. Connect via SSM:"
Write-Host "     aws ssm start-session --target $instanceId --region $Region"
Write-Host ""
Write-Host "  3. Set your GitHub token:"
Write-Host "     nano /opt/tazama/.env"
Write-Host "     (replace REPLACE_ME with your GH_TOKEN value)"
Write-Host ""
Write-Host "  4. Deploy the Tazama stack:"
Write-Host "     /opt/tazama/AWS_deployment/deploy-tazama.sh"
Write-Host ""
Write-Host "  5. Once deployed, users can access:"
Write-Host "     Demo UI:   http://$publicIp`:3011"
Write-Host "     TMS API:   http://$publicIp`:5000/documentation"
Write-Host "     Admin API: http://$publicIp`:5100/documentation"
Write-Host "============================================================"
