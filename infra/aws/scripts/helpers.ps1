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
      - Set-DemoUiOverlay    - apply tazama-demo public URL + SSM NEXTAUTH_SECRET
      - Set-ServerEnvOverlays - re-apply a server's full per-server AWS env overlays
      - Wait-Bootstrap       - poll until the bootstrap script has completed
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Constants ----------------------------------------------------------------
# Override any of these via environment variables before dot-sourcing:
#   $env:TAZAMA_AWS_REGION  - AWS region (default: ap-south-1)
#   $env:TAZAMA_AWS_PROFILE - AWS CLI profile name (default: tazama)
#   $env:TAZAMA_SSH_KEY     - Path to your SSH private key (default: ~/.ssh/id_ed25519)
$Script:AwsRegion  = if ($env:TAZAMA_AWS_REGION)  { $env:TAZAMA_AWS_REGION }  else { 'ap-south-1' }
$Script:AwsProfile = if ($env:TAZAMA_AWS_PROFILE) { $env:TAZAMA_AWS_PROFILE } else { 'tazama' }
$Script:KeyFile    = if ($env:TAZAMA_SSH_KEY)      { $env:TAZAMA_SSH_KEY }     else { "$env:USERPROFILE\.ssh\id_ed25519" }
$Script:RemoteRepo   = '/home/ec2-user/full-stack-docker-tazama'
$Script:RemoteUser   = 'ec2-user'
$Script:RepoBranch   = 'dev'
$Script:TemplatesDir = Join-Path $PSScriptRoot '..\templates'
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
            DemoPublicUrl      = if ($json.PSObject.Properties['demo_public_url']) { $json.demo_public_url.value } else { '' }
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
# Reads a KEY=VALUE overlay and applies each entry to the remote .env file at
# $RemoteEnvFile using sed:
#   - If the key exists: the value is replaced in-place.
#   - If the key is absent: the key=value line is appended.
#
# Supply EITHER -OverlayFile (path to a local .tpl file) OR -OverlayContent
# (a multi-line string of KEY=VALUE pairs).  Lines beginning with # are ignored.
function Set-RemoteEnvOverlay {
    param(
        [string]$InstanceId,
        [string]$OverlayFile,
        [string]$OverlayContent,
        [string]$RemoteEnvFile
    )

    $hasFile    = -not [string]::IsNullOrWhiteSpace($OverlayFile)
    $hasContent = -not [string]::IsNullOrWhiteSpace($OverlayContent)
    if ($hasFile -eq $hasContent) {
        throw "Set-RemoteEnvOverlay requires exactly one of -OverlayFile or -OverlayContent."
    }

    $source = if ($OverlayFile) { Get-Content $OverlayFile } `
              else               { $OverlayContent -split "`n" }

    $lines = $source | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' }

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

# -- Set-DemoUiOverlay --------------------------------------------------------
# When a custom domain is active, point the tazama-demo UI at its public HTTPS
# URL and source NEXTAUTH_SECRET from SSM. Both are written to core/.env; the
# demo service (docker-compose.base.auth.yaml) consumes them via
# ${DEMO_PUBLIC_URL} / ${DEMO_NEXTAUTH_SECRET} interpolation. Without this the
# committed localhost defaults apply (correct for local dev only).
#
# No-op when $DemoPublicUrl is empty (custom domain not enabled). Shared by
# deploy-core.ps1, deploy-service.ps1 and restart-service.ps1 so the demo env
# is re-applied consistently after any git reset --hard that restores defaults.
function Set-DemoUiOverlay {
    param(
        [string]$InstanceId,
        [string]$DemoPublicUrl,
        [string]$ServerLabel = 'Server A'
    )

    if (-not $DemoPublicUrl) { return }

    Write-Host "[$ServerLabel] Applying demo UI overlay (public URL + NEXTAUTH_SECRET from SSM)..."
    $demoOverlay = "DEMO_PUBLIC_URL=$DemoPublicUrl"
    $demoSecret = aws ssm get-parameter `
        --name /tazama/nextauth_secret `
        --with-decryption `
        --region $Script:AwsRegion `
        --profile $Script:AwsProfile `
        --query Parameter.Value `
        --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $demoSecret) {
        $demoOverlay += "`nDEMO_NEXTAUTH_SECRET=$demoSecret"
    } else {
        Write-Warning "[$ServerLabel] /tazama/nextauth_secret not found in SSM - demo UI falls back to the committed test secret. Set it with: aws ssm put-parameter --name /tazama/nextauth_secret --type SecureString --value <openssl rand -base64 32>"
    }
    Set-RemoteEnvOverlay -InstanceId $InstanceId `
        -OverlayContent $demoOverlay `
        -RemoteEnvFile "$Script:RemoteRepo/core/.env"
    Write-Host "[$ServerLabel] Demo UI overlay applied." -ForegroundColor Green
}

# -- Set-ServerEnvOverlays ----------------------------------------------------
# Re-apply the per-server AWS env overlays that must not be committed. A
# 'git reset --hard' on the target server restores the repo's committed
# (local-dev) defaults; this function restores the AWS-specific values:
#   Server A : extensions/.env (host names, public API URLs, CORS) unless
#              -SkipExtensionsOverlay; KEYCLOAK_HOSTNAME in core/.env; strips
#              KC_HOSTNAME_PORT from keycloak.env; and the tazama-demo public
#              URL + NEXTAUTH_SECRET (see Set-DemoUiOverlay).
#   Server B : extensions/.env overlay.
#   Server C : biar/.env overlay (host names, S3A_ENDPOINT, COUCHDB_URL).
#
# Shared by deploy-core.ps1, deploy-service.ps1 and restart-service.ps1 so the
# overlay set stays identical across initial deploys and post-reset restores.
# -SkipExtensionsOverlay is used by deploy-core.ps1, whose scope is the core
# stack only - the extensions/.env overlay on Server A is owned by
# deploy-extensions.ps1.
function Set-ServerEnvOverlays {
    param(
        [Parameter(Mandatory)][ValidateSet('A', 'B', 'C')][string]$Server,
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][hashtable]$TofuOutputs,
        [switch]$SkipExtensionsOverlay
    )

    $label = "Server $Server"

    switch ($Server) {
        'A' {
            if (-not $SkipExtensionsOverlay) {
                # extensions/.env: SERVER_A/B/C_HOST, public API URLs, CORS origins
                Write-Host "[$label] Re-applying extensions .env overlay..."
                Set-RemoteEnvOverlay -InstanceId $InstanceId `
                    -OverlayFile (Join-Path $Script:TemplatesDir 'env-extensions.tpl') `
                    -RemoteEnvFile "$Script:RemoteRepo/extensions/.env"
            }

            # core/.env: KEYCLOAK_HOSTNAME (only present when an ALB is active)
            if ($TofuOutputs.KeycloakHostname) {
                Write-Host "[$label] Applying KEYCLOAK_HOSTNAME to core/.env..."
                Set-RemoteEnvOverlay -InstanceId $InstanceId `
                    -OverlayContent "KEYCLOAK_HOSTNAME=$($TofuOutputs.KeycloakHostname)" `
                    -RemoteEnvFile "$Script:RemoteRepo/core/.env"
            }

            # KC_HOSTNAME_PORT must be absent on AWS - KC_PROXY=edge derives the
            # port from the ALB's X-Forwarded-Port: 443. The committed keycloak.env
            # carries KC_HOSTNAME_PORT=8080 for local use; strip it here.
            # TODO(#221): replace with Set-RemoteEnvOverlay deletion support.
            Write-Host "[$label] Stripping KC_HOSTNAME_PORT from keycloak.env..."
            Invoke-RemoteCommand -InstanceId $InstanceId `
                -Command "sed -i '/^KC_HOSTNAME_PORT=/d' $Script:RemoteRepo/core/env/keycloak.env"

            # core/.env: tazama-demo public URL + NEXTAUTH_SECRET (custom domain only)
            Set-DemoUiOverlay -InstanceId $InstanceId -DemoPublicUrl $TofuOutputs.DemoPublicUrl -ServerLabel $label
        }
        'B' {
            # extensions/.env: SERVER_A/B/C_HOST, public API URLs, CORS origins
            Write-Host "[$label] Re-applying extensions .env overlay..."
            Set-RemoteEnvOverlay -InstanceId $InstanceId `
                -OverlayFile (Join-Path $Script:TemplatesDir 'env-extensions.tpl') `
                -RemoteEnvFile "$Script:RemoteRepo/extensions/.env"
        }
        'C' {
            # biar/.env: SERVER_A/B/C_HOST, S3A_ENDPOINT, COUCHDB_URL
            Write-Host "[$label] Re-applying biar .env overlay..."
            Set-RemoteEnvOverlay -InstanceId $InstanceId `
                -OverlayFile (Join-Path $Script:TemplatesDir 'env-biar.tpl') `
                -RemoteEnvFile "$Script:RemoteRepo/biar/.env"
        }
    }
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
