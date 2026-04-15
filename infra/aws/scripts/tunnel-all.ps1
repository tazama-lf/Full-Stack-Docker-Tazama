# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Open SSH port-forward tunnels to all three servers simultaneously.

.DESCRIPTION
    Launches three background SSH tunnel jobs (one per server) and waits on
    all of them. Every service port across Server A, B, and C is forwarded to
    localhost simultaneously.

    Press Ctrl+C to close all tunnels.

.EXAMPLE
    .\tunnel-all.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$out  = Get-TofuOutputs
$idA  = $out.ServerA_InstanceId
$idB  = $out.ServerB_InstanceId
$idC  = $out.ServerC_InstanceId

$keyPath = (Resolve-Path $Script:KeyFile).Path -replace '\\', '/'

Write-Host ''
Write-Host '=== Tunnel: All Servers ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Server A (tazama-core):'
Write-Host '  5000  -> TMS API'
Write-Host '  5100  -> Admin API'
Write-Host '  3020  -> Auth Service'
Write-Host '  8080  -> Keycloak'
Write-Host '  6100  -> Hasura GraphQL'
Write-Host '  5050  -> pgAdmin'
Write-Host '  14222 -> NATS'
Write-Host '  15432 -> PostgreSQL'
Write-Host '  3001  -> DEAPI'
Write-Host '  3002  -> DEMS'
Write-Host ''
Write-Host 'Server B (tazama-extensions):'
Write-Host '  3010  -> TCS backend'
Write-Host '  5173  -> TCS frontend'
Write-Host '  3005  -> TRS backend'
Write-Host '  5174  -> TRS frontend'
Write-Host '  3090  -> CMS backend'
Write-Host '  5175  -> CMS frontend'
Write-Host '  8081  -> Flowable REST'
Write-Host '  5984  -> CouchDB'
Write-Host '  9200  -> OpenSearch'
Write-Host '  15433 -> PostgreSQL (CMS)'
Write-Host '  12222 -> SFTP'
Write-Host ''
Write-Host 'Server C (tazama-biar):'
Write-Host '  8088  -> NiFi'
Write-Host '  8983  -> Solr'
Write-Host '  9998  -> Apache Tika'
Write-Host '  9874  -> Ozone OM'
Write-Host '  9876  -> Ozone SCM'
Write-Host '  9878  -> Ozone S3 Gateway'
Write-Host '  9888  -> Ozone Recon'
Write-Host ''
Write-Host 'Press Ctrl+C to close all tunnels.' -ForegroundColor Yellow
Write-Host ''

# Build a temporary SSH config for each instance and launch as a background job.
function Start-TunnelJob {
    param(
        [string]$Label,
        [string]$InstanceId,
        [string]$KeyPath,
        [string[]]$Forwards,
        [string]$AwsExe,
        [string]$AwsRegion,
        [string]$AwsProfile,
        [string]$RemoteUser
    )

    $tmp = [System.IO.Path]::GetTempFileName()
    @"
Host $InstanceId
  HostName $InstanceId
  User $RemoteUser
  IdentityFile $KeyPath
  StrictHostKeyChecking no
  UserKnownHostsFile NUL
  ConnectTimeout 20
  ServerAliveInterval 10
  ServerAliveCountMax 2
  ProxyCommand $AwsExe ec2-instance-connect open-tunnel --instance-id %h --remote-port %p --region $AwsRegion --profile $AwsProfile
"@ | Set-Content $tmp -Encoding ASCII

    $fwdArgs = $Forwards | ForEach-Object { "-L", $_ }

    Start-Job -Name $Label -ScriptBlock {
        param($ssh, $fwd, $cfg, $id, $tmp)
        try {
            & $ssh -q -N @fwd -F $cfg $id
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList (Get-Command ssh).Source, $fwdArgs, $tmp, $InstanceId, $tmp
}

$commonArgs = @{
    KeyPath     = $keyPath
    AwsExe      = $Script:AwsExe
    AwsRegion   = $Script:AwsRegion
    AwsProfile  = $Script:AwsProfile
    RemoteUser  = $Script:RemoteUser
}

$jobA = Start-TunnelJob -Label 'TunnelA' -InstanceId $idA -Forwards @(
    '5000:localhost:5000', '5100:localhost:5100', '3020:localhost:3020',
    '8080:localhost:8080', '6100:localhost:6100', '5050:localhost:5050',
    '14222:localhost:14222', '15432:localhost:15432',
    '3001:localhost:3001', '3002:localhost:3002'
) @commonArgs

$jobB = Start-TunnelJob -Label 'TunnelB' -InstanceId $idB -Forwards @(
    '3010:localhost:3010', '5173:localhost:5173', '3005:localhost:3005',
    '5174:localhost:5174', '3090:localhost:3090', '5175:localhost:5175',
    '8081:localhost:8081', '5984:localhost:5984', '9200:localhost:9200',
    '15433:localhost:15433', '12222:localhost:12222'
) @commonArgs

$jobC = Start-TunnelJob -Label 'TunnelC' -InstanceId $idC -Forwards @(
    '8088:localhost:8088', '8983:localhost:8983', '9998:localhost:9998',
    '9874:localhost:9874', '9876:localhost:9876', '9878:localhost:9878',
    '9888:localhost:9888'
) @commonArgs

Write-Host "[TunnelA] started (job $($jobA.Id))" -ForegroundColor Green
Write-Host "[TunnelB] started (job $($jobB.Id))" -ForegroundColor Green
Write-Host "[TunnelC] started (job $($jobC.Id))" -ForegroundColor Green
Write-Host ''

try {
    # Stream job output and block until all three jobs finish (or Ctrl+C)
    Wait-Job -Job $jobA, $jobB, $jobC | Out-Null
}
finally {
    Write-Host ''
    Write-Host 'Stopping tunnels...' -ForegroundColor Yellow
    Stop-Job  -Job $jobA, $jobB, $jobC -ErrorAction SilentlyContinue
    Remove-Job -Job $jobA, $jobB, $jobC -Force -ErrorAction SilentlyContinue
    Write-Host 'All tunnels closed.' -ForegroundColor Yellow
}
