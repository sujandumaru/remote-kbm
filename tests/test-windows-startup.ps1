#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PythonPath
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$installerPath = Join-Path $projectRoot "windows\install-startup.ps1"
$launcherPath = Join-Path $projectRoot "windows\launch-background.pyw"

if (-not $PythonPath) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $pythonCommand) {
        throw "python.exe was not found for the Windows startup tests."
    }
    $PythonPath = $pythonCommand.Source
}

$basePythonPath = & $PythonPath -c "import sys; print(sys._base_executable)"
$basePythonwPath = Join-Path (Split-Path -Parent $basePythonPath) "pythonw.exe"
$sitePackagesPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PythonPath)) `
    "Lib\site-packages"
if (-not (Test-Path -LiteralPath $basePythonwPath)) {
    throw "Base pythonw.exe was not found at $basePythonwPath"
}

$testRoot = Join-Path $env:TEMP (
    "remote-kbm-startup-test-" + [guid]::NewGuid().ToString("N")
)
$fakeProjectRoot = Join-Path $testRoot "project"
$fakeServerDirectory = Join-Path $fakeProjectRoot "server"
$fakeClientDirectory = Join-Path $fakeProjectRoot "client"
$fakeServerPath = Join-Path $fakeServerDirectory "main.py"

function Invoke-WindowlessServer {
    param(
        [string]$LogPath,
        [switch]$ShowConnect
    )

    $arguments = '-S "{0}" "{1}" "{2}" "{3}"' -f `
        $launcherPath, $sitePackagesPath, $fakeServerPath, $LogPath
    if ($ShowConnect) {
        $arguments += " --show-connect"
    }
    return Start-Process `
        -FilePath $basePythonwPath `
        -ArgumentList $arguments `
        -Wait `
        -PassThru
}

try {
    New-Item `
        -ItemType Directory `
        -Path $fakeServerDirectory, $fakeClientDirectory `
        -Force | Out-Null
    Copy-Item `
        -Path (Join-Path $projectRoot "server\*.py") `
        -Destination $fakeServerDirectory
    Copy-Item `
        -Path (Join-Path $projectRoot "client\*") `
        -Destination $fakeClientDirectory `
        -Recurse

    $successLogPath = Join-Path $testRoot "success.log"
    $successProcess = Invoke-WindowlessServer `
        -LogPath $successLogPath `
        -ShowConnect
    $successLog = Get-Content -LiteralPath $successLogPath -Raw -Encoding UTF8

    if ($successProcess.ExitCode -ne 0) {
        throw "Windowless logging exited with code $($successProcess.ExitCode)."
    }
    if ($successLog -notmatch "http://") {
        throw "Windowless logging did not preserve the connection URL."
    }
    Write-Host "Windowless startup success path passed."

    $failureLogPath = Join-Path $testRoot "failure.log"
    $portBlocker = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Any,
        8765
    )
    $portBlocker.Start()
    try {
        $failureProcess = Invoke-WindowlessServer -LogPath $failureLogPath
    } finally {
        $portBlocker.Stop()
    }
    $failureLog = Get-Content -LiteralPath $failureLogPath -Raw -Encoding UTF8

    if ($failureProcess.ExitCode -eq 0) {
        throw "The server unexpectedly started while port 8765 was unavailable."
    }
    if ($failureLog -notmatch "Traceback" -or
        $failureLog -notmatch "8765") {
        throw "The windowless server did not record its startup failure."
    }

    Write-Host "Expected windowless startup failure captured:"
    Get-Content -LiteralPath $failureLogPath -Tail 8 -Encoding UTF8 |
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
    if ($installerText -notmatch "Requirements file not found") {
        throw "The installer failure was not printed in the terminal output."
    }

    Write-Host "Expected installer failure captured:"
    $installerOutput |
        ForEach-Object { Write-Host "  $($_.ToString())" }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
