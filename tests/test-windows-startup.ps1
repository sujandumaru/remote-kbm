#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PythonPath
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $projectRoot "windows\run-at-login.ps1"
$installerPath = Join-Path $projectRoot "windows\install-startup.ps1"

if (-not $PythonPath) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        throw "python.exe was not found for the Windows startup tests."
    }
    $PythonPath = $pythonCommand.Source
}

if (-not (Test-Path -LiteralPath $PythonPath)) {
    throw "Windows Python was not found at $PythonPath"
}

$testRoot = Join-Path $env:TEMP (
    "remote-kbm-startup-test-" + [guid]::NewGuid().ToString("N")
)
$fakeProjectRoot = Join-Path $testRoot "project"
$serverDirectory = Join-Path $fakeProjectRoot "server"
$serverPath = Join-Path $serverDirectory "main.py"
$testLocalAppData = Join-Path $testRoot "local"
$logPath = Join-Path $testLocalAppData "remote-kbm\server.log"

function Invoke-TestRunner {
    $savedLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $testLocalAppData
        & powershell.exe `
            -NoLogo `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $runnerPath `
            -ProjectRoot $fakeProjectRoot `
            -PythonPath $PythonPath
        return $LASTEXITCODE
    } finally {
        $env:LOCALAPPDATA = $savedLocalAppData
    }
}

try {
    New-Item -ItemType Directory -Path $serverDirectory -Force | Out-Null

    Set-Content `
        -LiteralPath $serverPath `
        -Value 'import logging; logging.warning("expected test message")' `
        -Encoding UTF8
    $successExitCode = Invoke-TestRunner
    $successLog = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8

    if ($successExitCode -ne 0) {
        throw "Ordinary Python logging caused runner exit code $successExitCode."
    }
    if ($successLog -notmatch "expected test message" -or
        $successLog -match "NativeCommandError") {
        throw "The runner did not preserve clean Python log output."
    }
    Write-Host "Startup runner success path passed."

    Set-Content `
        -LiteralPath $serverPath `
        -Value 'import sys; print("expected startup failure", file=sys.stderr); sys.exit(23)' `
        -Encoding UTF8
    $failureExitCode = Invoke-TestRunner
    $failureLog = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8

    if ($failureExitCode -ne 23) {
        throw "The runner returned $failureExitCode instead of the Python exit code 23."
    }
    if ($failureLog -notmatch "expected startup failure" -or
        $failureLog -notmatch "remote-kbm exited with code 23") {
        throw "The runner did not record the expected startup failure."
    }

    Write-Host "Expected runner failure captured:"
    Get-Content -LiteralPath $logPath -Tail 3 -Encoding UTF8 |
        ForEach-Object { Write-Host "  $_" }

    $brokenProjectRoot = Join-Path $testRoot "broken-project"
    $brokenWindowsDirectory = Join-Path $brokenProjectRoot "windows"
    $brokenInstallerPath = Join-Path $brokenWindowsDirectory "install-startup.ps1"
    New-Item -ItemType Directory -Path $brokenWindowsDirectory -Force | Out-Null
    Copy-Item -LiteralPath $installerPath -Destination $brokenInstallerPath

    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $installerOutput = @(
            & powershell.exe `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -ExecutionPolicy Bypass `
                -File $brokenInstallerPath 2>&1
        )
        $installerExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }

    $installerText = ($installerOutput | ForEach-Object { $_.ToString() }) -join "`n"
    if ($installerExitCode -eq 0) {
        throw "The incomplete installation unexpectedly succeeded."
    }
    if ($installerText -notmatch "Startup runner not found") {
        throw "The installer failure was not printed in the terminal output."
    }

    Write-Host "Expected installer failure captured:"
    $installerOutput |
        ForEach-Object { Write-Host "  $($_.ToString())" }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
