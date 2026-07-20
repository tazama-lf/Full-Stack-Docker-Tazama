# SPDX-License-Identifier: Apache-2.0
<#
.SYNOPSIS
    Dump Docker container logs from an AWS server (A, B, or C) to a local file.

.DESCRIPTION
    Connects to the specified EC2 instance via the EICE SSH tunnel and collects
    'docker logs' output for either a single container or every running
    container on that server. The combined output is written to a local file
    (default: aws-server-logs.txt in the current directory).

    By default only the last 50 log lines per container are captured; use -All
    to capture the complete log history instead.

    When -Container is omitted, the script iterates over every running container
    on the server and prefixes each block with a header so the sections are easy
    to tell apart.

.PARAMETER Server
    Which EC2 instance to target. One of: A, B, C.
    A = Server A (tazama-core)
    B = Server B (tazama-extensions)
    C = Server C (tazama-biar)

.PARAMETER Container
    The name (or ID) of a single container to dump logs for. When omitted, logs
    for all running containers on the server are dumped.

.PARAMETER Tail
    Number of trailing log lines to capture per container. Default: 50.
    Ignored when -All is supplied.

.PARAMETER All
    Capture the entire log history for each container instead of just the last
    -Tail lines.

.PARAMETER OutFile
    Path to the output file. Default: aws-server-logs.txt in the current
    directory.

.EXAMPLE
    .\dump-logs.ps1 -Server A
    # Last 50 lines of every running container on Server A -> aws-server-logs.txt

.EXAMPLE
    .\dump-logs.ps1 -Server B -Container tcs-api
    # Last 50 lines of the tcs-api container on Server B

.EXAMPLE
    .\dump-logs.ps1 -Server C -Container nifi -All
    # Full log history of the nifi container on Server C

.EXAMPLE
    .\dump-logs.ps1 -Server A -Container keycloak -Tail 200 -OutFile keycloak.txt
    # Last 200 lines of the keycloak container to a custom file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('A', 'B', 'C')]
    [string]$Server,

    [string]$Container,

    [int]$Tail = 50,

    [switch]$All,

    [string]$OutFile = 'aws-server-logs.txt'
)

. "$PSScriptRoot\helpers.ps1"

$out = Get-TofuOutputs

# -- Per-server: instance ID and project label ------------------------------------------------
switch ($Server) {
    'A' { $label = 'Server A'; $instanceId = $out.ServerA_InstanceId; $project = 'tazama-core'       }
    'B' { $label = 'Server B'; $instanceId = $out.ServerB_InstanceId; $project = 'tazama-extensions' }
    'C' { $label = 'Server C'; $instanceId = $out.ServerC_InstanceId; $project = 'tazama-biar'       }
}

# 'docker logs' tail expression: 'all' captures the full history.
$tailExpr = if ($All) { 'all' } else { "$Tail" }

Write-Host ''
Write-Host "=== Dump logs: $label ===" -ForegroundColor Cyan
Write-Host "[$label] Instance ID: $instanceId"
Write-Host "[$label] Project    : $project"
Write-Host "[$label] Container  : $(if ($Container) { $Container } else { '(all running)' })"
Write-Host "[$label] Tail       : $tailExpr"
Write-Host "[$label] Output     : $OutFile"
Write-Host ''

# -- Build the remote log-collection script --------------------------------------------------
# For a single container, dump its logs directly. For all containers, loop over
# every running container name and emit a header before each block so the output
# file is easy to navigate. --timestamps prefixes each line with an ISO time,
# and stderr is merged into stdout so both streams are captured.
if ($Container) {
    $remoteCmd = @'
set -e
NAME="CONTAINER_PLACEHOLDER"
if ! docker inspect "$NAME" >/dev/null 2>&1; then
  echo "ERROR: container '$NAME' not found on this server" >&2
  exit 1
fi
echo "========================================================================"
echo "Container: $NAME"
echo "========================================================================"
docker logs --timestamps --tail TAIL_PLACEHOLDER "$NAME" 2>&1
'@ -replace 'CONTAINER_PLACEHOLDER', $Container -replace 'TAIL_PLACEHOLDER', $tailExpr
}
else {
    $remoteCmd = @'
set -e
NAMES=$(docker ps --format '{{.Names}}' | sort)
if [ -z "$NAMES" ]; then
  echo "No running containers on this server." >&2
  exit 1
fi
for NAME in $NAMES; do
  echo "========================================================================"
  echo "Container: $NAME"
  echo "========================================================================"
  docker logs --timestamps --tail TAIL_PLACEHOLDER "$NAME" 2>&1
  echo ""
done
'@ -replace 'TAIL_PLACEHOLDER', $tailExpr
}

Write-Host "[$label] Collecting logs from server..."

# Capture the remote output. Invoke-RemoteCommand streams stdout back; collect
# it into a single string for writing to the local file.
$logs = Invoke-RemoteCommand -InstanceId $instanceId -Command $remoteCmd

# Prepend a small header identifying the source and capture time.
$header = @(
    "# Tazama AWS container logs"
    "# Server    : $label ($instanceId)"
    "# Project   : $project"
    "# Container : $(if ($Container) { $Container } else { 'all running containers' })"
    "# Tail      : $tailExpr"
    "# Captured  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    ""
) -join "`n"

Set-Content -Path $OutFile -Value ($header + ($logs -join "`n")) -Encoding UTF8

$resolved = (Resolve-Path $OutFile).Path
Write-Host "[$label] Logs written to $resolved" -ForegroundColor Green
