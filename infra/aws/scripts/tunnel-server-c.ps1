# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Open SSH port-forward tunnels to Server C (tazama-biar) services.

.DESCRIPTION
    Forwards a set of local ports to the corresponding service ports on
    Server C via the EICE SSH tunnel. While this script is running, browsers
    and other local tools can reach Server C services at localhost:<port>.

    Press Ctrl+C to close the tunnels.

.EXAMPLE
    .\tunnel-server-c.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs
$idC = $out.ServerC_InstanceId

Write-Host ''
Write-Host '=== Tunnel: Server C (tazama-biar) ===' -ForegroundColor Cyan
Write-Host "[Server C] Instance ID: $idC"
Write-Host ''
Write-Host 'Forwarded ports (localhost -> Server C):'
Write-Host '  7619  -> Automation Orchestrator API'
Write-Host '  8000  -> JupyterHub'
Write-Host '  8088  -> NiFi'
Write-Host '  8282  -> Datalakehouse API'
Write-Host '  8983  -> Solr'
Write-Host '  9998  -> Apache Tika'
Write-Host '  9874  -> Ozone OM (Object Manager)'
Write-Host '  9876  -> Ozone SCM (Storage Container Manager)'
Write-Host '  9878  -> Ozone S3 Gateway'
Write-Host '  9888  -> Ozone Recon'
Write-Host ''
Write-Host 'Press Ctrl+C to close all tunnels.' -ForegroundColor Yellow
Write-Host ''

$keyPath = (Resolve-Path $Script:KeyFile).Path -replace '\\', '/'
$tmp = [System.IO.Path]::GetTempFileName()
@"
Host $idC
  HostName $idC
  User $Script:RemoteUser
  IdentityFile $keyPath
  StrictHostKeyChecking no
  UserKnownHostsFile NUL
  ConnectTimeout 20
  ServerAliveInterval 10
  ServerAliveCountMax 2
  ProxyCommand $Script:AwsExe ec2-instance-connect open-tunnel --instance-id %h --remote-port %p --region $Script:AwsRegion --profile $Script:AwsProfile
"@ | Set-Content $tmp -Encoding ASCII

try {
    ssh -q -N `
        -L 7619:localhost:7619 `
        -L 8000:localhost:8000 `
        -L 8088:localhost:8088 `
        -L 8282:localhost:8282 `
        -L 8983:localhost:8983 `
        -L 9998:localhost:9998 `
        -L 9874:localhost:9874 `
        -L 9876:localhost:9876 `
        -L 9878:localhost:9878 `
        -L 9888:localhost:9888 `
        -F $tmp $idC
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
