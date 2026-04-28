# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Shared helpers for Tazama AWS deploy scripts.
    Dot-source this file from every deploy/teardown script:
        . "$PSScriptRoot\helpers.ps1"

.DESCRIPTION
    Provides:
      - Get-TofuOutputs     - reads tofu output -json for instance IDs / IPs
      - Invoke-RemoteCommand - SSH to an EC2 instance via EICE ProxyCommand
      - Copy-ToRemote        - SCP a file to an EC2 instance via EICE
      - Set-RemoteEnvOverlay - apply KEY=VALUE overlay to a remote .env file
      - Wait-Bootstrap       - poll until the bootstrap script has completed
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Constants ----------------------------------------------------------------
# Adjust these if you deploy to a different region or use a different profile.
$Script:AwsRegion  = 'ap-south-1'
$Script:AwsProfile = 'tazama'
$Script:KeyFile    = "$env:USERPROFILE\.ssh\tazama_ed25519"
$Script:RemoteRepo   = '/home/ec2-user/full-stack-docker-tazama'
$Script:RemoteUser   = 'ec2-user'
$Script:RepoBranch   = 'dev'
# Resolve aws.exe to its full path so OpenSSH can execute it in a ProxyCommand.
# When OpenSSH spawns ProxyCommand it may not inherit PowerShell's PATH.
$Script:AwsExe = (Get-Command aws -ErrorAction SilentlyContinue).Source
if (-not $Script:AwsExe) { $Script:AwsExe = 'aws' }
# -- Get-TofuOutputs ----------------------------------------------------------
# Runs `tofu output -json` from the infra/aws directory and returns a hashtable:
#   .ServerA_InstanceId  .ServerB_InstanceId  .ServerC_InstanceId
#   .ServerA_PrivateIp   .ServerB_PrivateIp   .ServerC_PrivateIp
#   .EiceEndpointId
function Get-TofuOutputs {
    Push-Location (Join-Path $PSScriptRoot '..')
    try {
        $json = (tofu output -json) | ConvertFrom-Json
        return @{
            ServerA_InstanceId = $json.server_a_instance_id.value
            ServerB_InstanceId = $json.server_b_instance_id.value
            ServerC_InstanceId = $json.server_c_instance_id.value
            ServerA_PrivateIp  = $json.server_a_private_ip.value
            ServerB_PrivateIp  = $json.server_b_private_ip.value
            ServerC_PrivateIp  = $json.server_c_private_ip.value
            EiceEndpointId     = $json.eice_endpoint_id.value
            AlbDnsName         = if ($json.PSObject.Properties['alb_dns_name']) { $json.alb_dns_name.value } else { '' }
            KeycloakHostname   = if ($json.PSObject.Properties['keycloak_hostname']) { $json.keycloak_hostname.value } else { '' }
        }
    }
    finally {
        Pop-Location
    }
}

# -- New-SshConfig (internal) -------------------------------------------------
# Writes a temporary SSH config file for one instance and returns its path.
# The config uses the EICE ProxyCommand so no port 22 needs to be open.
# Caller is responsible for deleting the file when done.
function New-SshConfig {
    param([string]$InstanceId)

    # Resolve-Path gives us an absolute path; replace backslashes for OpenSSH.
    $keyPath = (Resolve-Path $Script:KeyFile).Path -replace '\\', '/'

    $content = @"
Host $InstanceId
  HostName $InstanceId
  User $Script:RemoteUser
  IdentityFile $keyPath
  StrictHostKeyChecking no
  UserKnownHostsFile NUL
  ConnectTimeout 20
  ServerAliveInterval 10
  ServerAliveCountMax 2
  ProxyCommand $Script:AwsExe ec2-instance-connect open-tunnel --instance-id %h --remote-port %p --region $Script:AwsRegion --profile $Script:AwsProfile
"@
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content $tmp $content -Encoding ASCII
    return $tmp
}

# -- Invoke-RemoteCommand -----------------------------------------------------
# Runs $Command on the remote EC2 instance identified by $InstanceId via EICE.
# Throws on non-zero SSH exit code.
function Invoke-RemoteCommand {
    param(
        [string]$InstanceId,
        [string]$Command
    )

    # Strip CR characters so Windows here-strings don't produce \r\n line endings
    # that bash rejects with "command not found".
    $Command = $Command -replace "`r", ''

    $cfg = New-SshConfig $InstanceId
    try {
        ssh -q -F $cfg $InstanceId $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Remote command failed (exit $LASTEXITCODE): $Command"
        }
    }
    finally {
        Remove-Item $cfg -Force -ErrorAction SilentlyContinue
    }
}

# -- Copy-ToRemote -------------------------------------------------------------
# SCP $LocalPath to $RemotePath on the remote instance via EICE.
# $RemotePath may contain ~ (e.g. ~/full-stack-docker-tazama/...).
function Copy-ToRemote {
    param(
        [string]$InstanceId,
        [string]$LocalPath,
        [string]$RemotePath
    )

    $cfg = New-SshConfig $InstanceId
    try {
        scp -q -F $cfg $LocalPath "${InstanceId}:${RemotePath}"
        if ($LASTEXITCODE -ne 0) {
            throw "SCP failed (exit $LASTEXITCODE): $LocalPath -> $RemotePath"
        }
    }
    finally {
        Remove-Item $cfg -Force -ErrorAction SilentlyContinue
    }
}

# -- Set-RemoteEnvOverlay -----------------------------------------------------
# Reads a KEY=VALUE overlay file (lines beginning with # are ignored) and
# applies each entry to the remote .env file at $RemoteEnvFile using sed:
#   - If the key exists: the value is replaced in-place.
#   - If the key is absent: the key=value line is appended.
function Set-RemoteEnvOverlay {
    param(
        [string]$InstanceId,
        [string]$OverlayFile,
        [string]$RemoteEnvFile
    )

    $lines = Get-Content $OverlayFile |
             Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' }

    if (-not $lines) { return }

    # Build all sed/append commands as a single bash script and run them in one
    # SSH connection. Opening one EICE tunnel per key causes rate-limit hangs
    # when the overlay has many entries.
    #
    # Security: values may contain single quotes (passwords), pipe characters
    # (URLs), or other shell metacharacters. Mitigations applied:
    #   1. POSIX-escape values: replace every ' with '\'' before inlining.
    #   2. Use a control character (\x01) as the sed delimiter so | in values
    #      cannot break the sed expression.
    #   3. Use an explicit if/then/else instead of "&& ... ||" so a sed failure
    #      does not trigger the append branch and create duplicate KEY= lines.
    $bashLines = foreach ($line in $lines) {
        $key   = ($line -split '=', 2)[0].Trim()
        $value = ($line -split '=', 2)[1].Trim()
        # Escape single quotes for POSIX shell: ' -> '\''.
        $vEsc  = $value -replace "'", "'\''" 
        # \x01 is used as the sed delimiter; it cannot appear in env values.
        "if grep -q '^${key}=' ${RemoteEnvFile}; then " +
        "sed -i 's`u{1}^${key}=.*`u{1}${key}=${vEsc}`u{1}' ${RemoteEnvFile}; " +
        "else printf '%s\n' '${key}=${vEsc}' >> ${RemoteEnvFile}; fi"
    }
    $batchCmd = $bashLines -join '; '
    Invoke-RemoteCommand $InstanceId $batchCmd
}

# -- Wait-Bootstrap ------------------------------------------------------------
# Polls every 30 seconds until /home/ec2-user/.bootstrap-complete exists on
# the remote instance, or until $TimeoutMinutes have elapsed.
function Wait-Bootstrap {
    param(
        [string]$InstanceId,
        [string]$ServerName,
        [int]   $TimeoutMinutes = 15
    )

    Write-Host "[$ServerName] Waiting for bootstrap to complete (timeout: ${TimeoutMinutes}m)..."
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    while ((Get-Date) -lt $deadline) {
        $cfg = New-SshConfig $InstanceId
        try {
            ssh -q -F $cfg $InstanceId 'test -f /home/ec2-user/.bootstrap-complete'
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[$ServerName] Bootstrap complete." -ForegroundColor Green
                return
            }
        }
        catch { }
        finally {
            Remove-Item $cfg -Force -ErrorAction SilentlyContinue
        }
        Write-Host "[$ServerName]   still bootstrapping - retrying in 30s"
        Start-Sleep -Seconds 30
    }

    throw "[$ServerName] Bootstrap did not complete within $TimeoutMinutes minutes. Check /var/log/tazama-bootstrap.log on the instance."
}
