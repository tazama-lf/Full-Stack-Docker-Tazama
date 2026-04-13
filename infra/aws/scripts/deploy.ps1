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
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host '  Tazama Full-Stack Deploy'                            -ForegroundColor Cyan
Write-Host '=====================================================' -ForegroundColor Cyan

& "$PSScriptRoot\deploy-core.ps1"
& "$PSScriptRoot\deploy-extensions.ps1"
& "$PSScriptRoot\deploy-biar.ps1"

Write-Host ''
Write-Host '=====================================================' -ForegroundColor Green
Write-Host '  All stacks deployed successfully.'                   -ForegroundColor Green
Write-Host '=====================================================' -ForegroundColor Green
