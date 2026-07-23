# SPDX-License-Identifier: Apache-2.0
# teardown-tazama-sandbox.ps1
#
# Terminates the Tazama sandbox EC2 instance and releases the Elastic IP.
# Reads instance details from sandbox-state.json (written by deploy-tazama-sandbox.ps1).
#
# Optionally also removes the security group and IAM role/instance profile.
# These are safe to keep between deployments (they can be reused), but use
# -CleanupAll if you want a complete teardown with no leftover resources.
#
# Usage:
#   .\teardown-tazama-sandbox.ps1
#   .\teardown-tazama-sandbox.ps1 -CleanupAll

param(
    # Also delete the security group, IAM role, and instance profile.
    # Only use this if you do not intend to redeploy the sandbox.
    [switch]$CleanupAll
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# 1. Load state
# ---------------------------------------------------------------------------
$stateFile = "$PSScriptRoot\sandbox-state.json"

if (-not (Test-Path $stateFile)) {
    Write-Host "ERROR: sandbox-state.json not found at $stateFile"
    Write-Host "       Cannot proceed without instance ID and allocation ID."
    Write-Host "       If the state file was lost, find the instance in the AWS console"
    Write-Host "       and terminate it manually, then release the Elastic IP."
    exit 1
}

$state = Get-Content $stateFile | ConvertFrom-Json
$instanceId   = $state.instanceId
$allocationId = $state.allocationId
$publicIp     = $state.publicIp
$sgId         = $state.sgId
$region       = $state.region
$roleName     = $state.roleName
$profileName  = $state.profileName

Write-Host "Loaded state from $stateFile"
Write-Host "  Instance ID:  $instanceId"
Write-Host "  Public IP:    $publicIp"
Write-Host "  Region:       $region"
Write-Host ""

# ---------------------------------------------------------------------------
# 2. Confirm before proceeding
# ---------------------------------------------------------------------------
$confirm = Read-Host "This will TERMINATE the EC2 instance and release the Elastic IP. Type 'yes' to confirm"
if ($confirm -ne "yes") {
    Write-Host "Aborted. No changes made."
    exit 0
}

# ---------------------------------------------------------------------------
# 3. Terminate EC2 instance
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Terminating EC2 instance ---"
aws ec2 terminate-instances --instance-ids $instanceId --region $region | Out-Null
Write-Host "Termination initiated for $instanceId. Waiting for terminated state..."
aws ec2 wait instance-terminated --instance-ids $instanceId --region $region
Write-Host "Instance terminated."

# ---------------------------------------------------------------------------
# 4. Release Elastic IP
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "--- Releasing Elastic IP ---"
aws ec2 release-address --allocation-id $allocationId --region $region
Write-Host "Elastic IP $publicIp released."

# ---------------------------------------------------------------------------
# 5. Optional: clean up security group, IAM role, and instance profile
# ---------------------------------------------------------------------------
if ($CleanupAll) {
    Write-Host ""
    Write-Host "--- Cleaning up security group ---"
    try {
        aws ec2 delete-security-group --group-id $sgId --region $region
        Write-Host "Security group $sgId deleted."
    } catch {
        Write-Host "WARNING: Could not delete security group $sgId - it may still have dependencies."
        Write-Host "         Delete it manually in the AWS console if needed."
    }

    Write-Host ""
    Write-Host "--- Cleaning up IAM instance profile ---"
    try {
        aws iam remove-role-from-instance-profile `
            --instance-profile-name $profileName `
            --role-name $roleName
        aws iam delete-instance-profile --instance-profile-name $profileName
        Write-Host "Instance profile $profileName deleted."
    } catch {
        Write-Host "WARNING: Could not delete instance profile $profileName"
    }

    Write-Host ""
    Write-Host "--- Cleaning up IAM role ---"
    try {
        aws iam detach-role-policy `
            --role-name $roleName `
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        aws iam delete-role --role-name $roleName
        Write-Host "IAM role $roleName deleted."
    } catch {
        Write-Host "WARNING: Could not delete IAM role $roleName"
    }
}

# ---------------------------------------------------------------------------
# 6. Archive state file
# ---------------------------------------------------------------------------
$archivePath = "$PSScriptRoot\sandbox-state.terminated-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
Rename-Item -Path $stateFile -NewName $archivePath
Write-Host ""
Write-Host "State file archived to: $archivePath"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host "Teardown complete."
Write-Host "  Instance $instanceId terminated."
Write-Host "  Elastic IP $publicIp released."
if ($CleanupAll) {
    Write-Host "  Security group, IAM role, and instance profile removed."
} else {
    Write-Host ""
    Write-Host "  Security group ($sgId), IAM role ($roleName), and instance"
    Write-Host "  profile ($profileName) were kept and can be reused for the"
    Write-Host "  next deployment. Run with -CleanupAll to remove them."
}
Write-Host "============================================================"
