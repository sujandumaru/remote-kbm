#Requires -Version 5.1
<#
.SYNOPSIS
Removes remote-kbm automatic startup for the current Windows user.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$taskName = "remote-kbm"
$runnerPath = Join-Path $env:LOCALAPPDATA "remote-kbm\run-at-login.ps1"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (-not $task) {
    Write-Host "The '$taskName' startup task is not installed."
    Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
    exit 0
}

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue

Write-Host "Automatic startup removed and its running task stopped."
Write-Host "The diagnostic log was kept at $env:LOCALAPPDATA\remote-kbm\server.log"
