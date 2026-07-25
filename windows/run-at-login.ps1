#Requires -Version 5.1
<#
Internal scheduled-task runner. Use install-startup.ps1 instead of invoking
this file directly.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [Parameter(Mandatory)]
    [string]$PythonPath
)

$ErrorActionPreference = "Stop"
$serverPath = Join-Path $ProjectRoot "server\main.py"
$logDirectory = Join-Path $env:LOCALAPPDATA "remote-kbm"
$logFile = Join-Path $logDirectory "server.log"

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
if ((Test-Path -LiteralPath $logFile) -and
    (Get-Item -LiteralPath $logFile).Length -gt 5MB) {
    Move-Item -LiteralPath $logFile -Destination "$logFile.1" -Force
}

function Write-StartupLog {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $logFile -Value "[$timestamp] $Message"
}

try {
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $serverPath)) {
        if ((Get-Date) -ge $deadline) {
            throw "Installed server script did not become available: $serverPath"
        }
        Start-Sleep -Seconds 2
    }

    if (-not (Test-Path -LiteralPath $PythonPath)) {
        throw "Installed Windows Python environment was not found: $PythonPath"
    }
    $env:PYTHONUNBUFFERED = "1"

    Write-StartupLog "Starting remote-kbm from $serverPath"
    & $PythonPath $serverPath *>> $logFile
    $serverExitCode = $LASTEXITCODE
    Write-StartupLog "remote-kbm exited with code $serverExitCode"
    exit $serverExitCode
} catch {
    Write-StartupLog "Startup failed: $($_.Exception.Message)"
    exit 1
}
