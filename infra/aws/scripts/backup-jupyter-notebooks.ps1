# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Backs up all JupyterHub user notebooks from Server C to a local timestamped archive.

.DESCRIPTION
    User workspaces live in the Docker volume tazama-biar_jupyterhub_notebooks
    (mounted at /srv/notebooks in the biar-jupyterhub container). This script:
      1. Creates a gzipped tar of the volume on Server C (requires sudo on the host).
      2. Downloads it via scp to the local backup directory.
      3. Removes the temporary archive from the server.

    Checkpoint files (.ipynb_checkpoints) are excluded by default; pass
    -IncludeCheckpoints to keep them.

.PARAMETER BackupDir
    Local directory to store the archive. Default: <repo>\backups\jupyter

.PARAMETER SshHost
    SSH host alias for Server C. Default: tazama-c

.PARAMETER IncludeCheckpoints
    Include .ipynb_checkpoints directories in the archive.

.EXAMPLE
    .\backup-jupyter-notebooks.ps1
    .\backup-jupyter-notebooks.ps1 -BackupDir D:\Backups\Tazama -IncludeCheckpoints
#>
param(
    [string]$BackupDir = (Join-Path $PSScriptRoot "..\..\..\backups\jupyter"),
    [string]$SshHost = "tazama-c",
    [switch]$IncludeCheckpoints
)

$ErrorActionPreference = "Stop"

$volumePath = "/var/lib/docker/volumes/tazama-biar_jupyterhub_notebooks/_data"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$archiveName = "jupyterhub-notebooks-$stamp.tar.gz"
$remoteTmp = "/tmp/$archiveName"

$excludeArg = if ($IncludeCheckpoints) { "" } else { "--exclude='.ipynb_checkpoints'" }

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$localPath = Join-Path (Resolve-Path $BackupDir) $archiveName

Write-Host "Creating archive on $SshHost ..."
ssh $SshHost "sudo tar czf $remoteTmp $excludeArg -C $volumePath . && sudo chown `$(whoami) $remoteTmp"
if ($LASTEXITCODE -ne 0) { throw "Remote archive creation failed." }

Write-Host "Downloading to $localPath ..."
scp "${SshHost}:$remoteTmp" $localPath
if ($LASTEXITCODE -ne 0) { throw "Download failed. Archive left on server at $remoteTmp" }

Write-Host "Cleaning up remote temp file ..."
ssh $SshHost "rm -f $remoteTmp"

$size = "{0:N1} MB" -f ((Get-Item $localPath).Length / 1MB)
Write-Host "Done: $localPath ($size)" -ForegroundColor Green
