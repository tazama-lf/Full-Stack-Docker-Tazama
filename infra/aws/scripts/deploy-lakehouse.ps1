# SPDX-License-Identifier: Apache-2.0
#
# deploy-lakehouse.ps1
# Stages a large Lakehouse zip archive through S3 and unpacks it on Server C
# into /opt/Warehouse.
#
# Why S3 and not SCP?  The file is typically 3-4 GB.  EICE tunnels are
# stdio-based and throttled — SCP over EICE for that size would take hours
# or time out.  Uploading to S3 from your workstation and then pulling it
# from S3 on Server C (same AWS region, internal network) is dramatically
# faster and more reliable.
#
# Prerequisites:
#   - The IAM role attached to every EC2 instance has a scoped read policy on
#     the lakehouse-staging/ prefix of the state bucket (added to main.tf).
#   - Your local AWS profile has s3:PutObject + s3:DeleteObject on the same
#     bucket (it already does — you created the bucket in Phase B).
#
# Usage (from infra\aws):
#   .\scripts\deploy-lakehouse.ps1 -ZipPath "D:\DevTools\Tazama\Tazama_Lakehouse.zip"

param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptsDir\helpers.ps1"

if (-not (Test-Path $ZipPath)) {
    throw "Zip file not found: $ZipPath"
}

Write-Host "Reading OpenTofu outputs..."
$out = Get-TofuOutputs
$instanceId = $out.ServerC_InstanceId
Write-Host "Server C instance: $instanceId"

# Resolve state bucket name from tofu variable (falls back to reading terraform.tfvars)
$stateBucket = tofu output -raw state_bucket 2>$null
if (-not $stateBucket) {
    # Parse directly from terraform.tfvars as fallback
    $stateBucket = (Get-Content "$PSScriptRoot\..\terraform.tfvars" |
                    Select-String 'state_bucket\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
}
if (-not $stateBucket) {
    throw "Could not determine state_bucket. Ensure it is set in terraform.tfvars."
}
Write-Host "Staging bucket: $stateBucket"

$s3Key     = "lakehouse-staging/Tazama_Lakehouse.zip"
$s3Uri     = "s3://$stateBucket/$s3Key"
$warehouseDir = "/opt/Warehouse"
$region    = "ap-south-1"
$profile   = "tazama"

# 1. Upload to S3 from local machine
Write-Host ""
Write-Host "Uploading $(Split-Path $ZipPath -Leaf) to $s3Uri ..."
Write-Host "(This may take several minutes for a large file)"
# Use 256 MB chunks (≈15 parts for a 3-4 GB file) instead of the default
# 8 MB chunks (≈475 parts). Fewer parts means fewer TCP handshakes and far
# less exposure to mid-transfer connection drops.
# multipart_chunksize is a config setting, not a CLI flag.
aws configure set s3.multipart_chunksize 256MB --profile $profile
aws configure set s3.multipart_threshold 256MB --profile $profile
aws s3 cp $ZipPath $s3Uri --region $region --profile $profile
if ($LASTEXITCODE -ne 0) { throw "S3 upload failed" }
Write-Host "Upload complete."

# 2. On Server C: download from S3, unpack, clean up
Write-Host ""
Write-Host "Downloading and unpacking on Server C ($instanceId) ..."
Invoke-RemoteCommand -InstanceId $instanceId -Command @"
set -e
# Install unzip if missing (Amazon Linux 2 / AL2023)
if ! command -v unzip &>/dev/null; then
    sudo yum install -y unzip 2>&1 | tail -3
fi
# Ensure destination exists (deploy-biar.ps1 creates it, but be safe)
sudo mkdir -p $warehouseDir
# Download from S3 — uses the instance IAM role, no credentials needed
echo "Downloading from S3..."
aws s3 cp $s3Uri /home/ec2-user/Tazama_Lakehouse.zip --region $region
# Unpack to / — the zip already contains the full path (opt/Warehouse/...)
# so extracting to -d / lands files at /opt/Warehouse/ directly.
# Using -d $warehouseDir would double-nest the path.
echo "Unpacking..."
sudo unzip -o /home/ec2-user/Tazama_Lakehouse.zip -d /
sudo chown -R root:root $warehouseDir
# Remove local copy
rm -f /home/ec2-user/Tazama_Lakehouse.zip
echo "--- Contents of $warehouseDir ---"
ls -lh $warehouseDir
"@

# 3. Remove the staging object from S3
Write-Host ""
Write-Host "Removing staging object from S3..."
aws s3 rm $s3Uri --region $region --profile $profile
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not delete staging object $s3Uri — remove it manually to avoid storage costs."
} else {
    Write-Host "Staging object deleted."
}

Write-Host ""
Write-Host "Lakehouse archive deployed to $warehouseDir on Server C."
