# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Open SSH port-forward tunnels to Server B (tazama-extensions) services.

.DESCRIPTION
    Forwards a set of local ports to the corresponding service ports on
    Server B via the EICE SSH tunnel. While this script is running, browsers
    and other local tools can reach Server B services at localhost:<port>.

    Press Ctrl+C to close the tunnels.

.EXAMPLE
    .\tunnel-server-b.ps1
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs
$idB = $out.ServerB_InstanceId

Write-Host ''
Write-Host '=== Tunnel: Server B (tazama-extensions) ===' -ForegroundColor Cyan
Write-Host "[Server B] Instance ID: $idB"
Write-Host ''
Write-Host 'Forwarded ports (localhost -> Server B):'
Write-Host '  3010  -> TCS (Connection Studio) backend'
Write-Host '  5173  -> TCS (Connection Studio) frontend'
Write-Host '  3005  -> TRS (Rule Studio) backend'
Write-Host '  5174  -> TRS (Rule Studio) frontend'
Write-Host '  3090  -> CMS (Case Management) backend'
Write-Host '  5175  -> CMS (Case Management) frontend'
Write-Host '  8081  -> Flowable REST'
Write-Host '  5984  -> CouchDB'
Write-Host '  9200  -> OpenSearch'
Write-Host '  15433 -> PostgreSQL (CMS)'
Write-Host '  12222 -> SFTP'
Write-Host ''
Write-Host 'Press Ctrl+C to close all tunnels.' -ForegroundColor Yellow
Write-Host ''

$keyPath = (Resolve-Path $Script:KeyFile).Path -replace '\\', '/'
$tmp = [System.IO.Path]::GetTempFileName()
@"
Host $idB
  HostName $idB
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
        -L 3010:localhost:3010 `
        -L 5173:localhost:5173 `
        -L 3005:localhost:3005 `
        -L 5174:localhost:5174 `
        -L 3090:localhost:3090 `
        -L 5175:localhost:5175 `
        -L 8081:localhost:8081 `
        -L 5984:localhost:5984 `
        -L 9200:localhost:9200 `
        -L 15433:localhost:15433 `
        -L 12222:localhost:12222 `
        -F $tmp $idB
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
