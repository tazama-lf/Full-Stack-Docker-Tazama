# SPDX-License-Identifier: Apache-2.0
#
# deploy-lakehouse.ps1
# Copies a Lakehouse zip archive to Server C and unpacks it into
# /opt/Tazama_Warehouse.
#
# Usage:
#   .\deploy-lakehouse.ps1 -ZipPath "C:\Tazama_Lakehouse.zip"

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

$remoteZip = "/home/ec2-user/Tazama_Lakehouse.zip"
$warehouseDir = "/opt/Tazama_Warehouse"

# 1. Copy zip to Server C home directory
Write-Host "Copying $ZipPath -> ${instanceId}:${remoteZip} ..."
Copy-ToRemote -InstanceId $instanceId -LocalPath $ZipPath -RemotePath $remoteZip

# 2. Ensure unzip is available, create target dir, unpack
Write-Host "Unpacking into $warehouseDir ..."
Invoke-RemoteCommand -InstanceId $instanceId -Command @"
set -e
# Install unzip if missing (Amazon Linux 2 / AL2023)
if ! command -v unzip &>/dev/null; then
    sudo yum install -y unzip 2>&1 | tail -3
fi
# Ensure destination exists
sudo mkdir -p $warehouseDir
# Unzip; -o overwrites existing files, -d sets destination
sudo unzip -o $remoteZip -d $warehouseDir
# Fix ownership so the biar containers (running as root) can access
sudo chown -R root:root $warehouseDir
# Show what was unpacked
echo "--- Contents of $warehouseDir ---"
ls -lh $warehouseDir
"@

# 3. Remove the zip from the server to free space
Write-Host "Cleaning up remote zip..."
Invoke-RemoteCommand -InstanceId $instanceId -Command "rm -f $remoteZip"

Write-Host ""
Write-Host "Lakehouse archive deployed to $warehouseDir on Server C."
