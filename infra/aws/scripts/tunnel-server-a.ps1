# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Open SSH port-forward tunnels to Server A (tazama-core) services.

.DESCRIPTION
    Forwards a set of local ports to the corresponding service ports on
    Server A via the EICE SSH tunnel. While this script is running, Postman
    and other local tools can reach Server A services at localhost:<port>.

    Press Ctrl+C to close the tunnels.

.EXAMPLE
    .\tunnel-server-a.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs
$idA = $out.ServerA_InstanceId

Write-Host ''
Write-Host '=== Tunnel: Server A (tazama-core) ===' -ForegroundColor Cyan
Write-Host "[Server A] Instance ID: $idA"
Write-Host ''
Write-Host 'Forwarded ports (localhost -> Server A):'
Write-Host '  5000  -> TMS API'
Write-Host '  5100  -> Admin API'
Write-Host '  3020  -> Auth Service'
Write-Host '  8080  -> Keycloak'
Write-Host '  6100  -> Hasura GraphQL'
Write-Host '  5050  -> pgAdmin'
Write-Host '  14222 -> NATS'
Write-Host '  15432 -> PostgreSQL'
Write-Host '  3001  -> DEAPI (Data Enrichment API)'
Write-Host '  3002  -> DEMS (Data Enrichment Monitoring Service)'
Write-Host ''
Write-Host 'Press Ctrl+C to close all tunnels.' -ForegroundColor Yellow
Write-Host ''

$keyPath = (Resolve-Path $Script:KeyFile).Path -replace '\\', '/'
$tmp = [System.IO.Path]::GetTempFileName()
@"
Host $idA
  HostName $idA
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
        -L 5000:localhost:5000 `
        -L 5100:localhost:5100 `
        -L 3020:localhost:3020 `
        -L 8080:localhost:8080 `
        -L 6100:localhost:6100 `
        -L 5050:localhost:5050 `
        -L 14222:localhost:14222 `
        -L 15432:localhost:15432 `
        -L 3001:localhost:3001 `
        -L 3002:localhost:3002 `
        -F $tmp $idA
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
