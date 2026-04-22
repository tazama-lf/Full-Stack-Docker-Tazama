# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Deploy all three Tazama stacks in sequence.

.DESCRIPTION
    Runs deploy-core.ps1, deploy-extensions.ps1, and deploy-biar.ps1 in
    order.  Each script waits for its server's bootstrap to complete before
    proceeding, so this script is safe to run immediately after `tofu apply`.

    Run from infra/aws/scripts/ or anywhere - paths are resolved relative
    to this script's location.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Password 'your-strong-password'
#>

[CmdletBinding()]
param(
    [switch]$NoPull,

    # PostgreSQL and Keycloak admin password for the cloud deployment.
    # Passed through to deploy-core.ps1 and deploy-extensions.ps1.
    # If omitted, local-dev defaults ('unused' / 'password') are left in place.
    [string]$Password = ''
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host '  Tazama Full-Stack Deploy'                            -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Cyan

$passArgs = if ($Password) { @('-Password', $Password) } else { @() }
$pullArgs  = if ($NoPull)  { @('-NoPull') }              else { @() }

& "$PSScriptRoot\deploy-core.ps1"       @passArgs @pullArgs
& "$PSScriptRoot\deploy-extensions.ps1" @passArgs @pullArgs
& "$PSScriptRoot\deploy-biar.ps1"       @pullArgs

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Green
Write-Host '  All stacks deployed successfully.'                   -ForegroundColor Green
Write-Host '=====================================================' -ForegroundColor Green
