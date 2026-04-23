# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Adds a user's SSH public key to authorized_keys on one or more Tazama EC2 servers.

.DESCRIPTION
    Appends the supplied public key to ~/.ssh/authorized_keys on Server A, B, and/or C
    via the EC2 Instance Connect Endpoint (no bastion, no VPN required).
    Duplicate detection is performed — the key is only appended if it is not already present.

.PARAMETER PublicKey
    The full SSH public key string to add. Must start with a key type (e.g. "ssh-ed25519 AAAA...").
    Pass the contents of the user's .pub file as a single line.

.PARAMETER Servers
    Which servers to add the key to. Accepts one or more of: A, B, C.
    Defaults to all three.

.EXAMPLE
    .\add-ssh-key.ps1 -PublicKey "ssh-ed25519 AAAA... user@host"

.EXAMPLE
    .\add-ssh-key.ps1 -PublicKey "ssh-ed25519 AAAA... user@host" -Servers A,C
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^(ssh-|ecdsa-)[A-Za-z0-9+/]')]
    [string] $PublicKey,

    [Parameter()]
    [ValidateSet('A', 'B', 'C')]
    [string[]] $Servers = @('A', 'B', 'C')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\helpers.ps1"
$out = Get-TofuOutputs

$serverMap = [ordered]@{
    A = @{ Name = 'Server A (core)';       InstanceId = $out.ServerA_InstanceId }
    B = @{ Name = 'Server B (extensions)'; InstanceId = $out.ServerB_InstanceId }
    C = @{ Name = 'Server C (biar)';       InstanceId = $out.ServerC_InstanceId }
}

foreach ($s in $Servers) {
    $server = $serverMap[$s]
    Write-Host "[$($server.Name)] Adding key..." -ForegroundColor Cyan

    $cmd = @"
if grep -qF -- '$PublicKey' ~/.ssh/authorized_keys 2>/dev/null; then
  echo "  Key already present - skipped."
else
  echo '$PublicKey' >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
  echo "  Key added successfully."
fi
"@

    Invoke-RemoteCommand -InstanceId $server.InstanceId -Command $cmd
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
