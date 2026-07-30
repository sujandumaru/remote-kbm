#Requires -Version 5.1
<#
.SYNOPSIS
Registers remote-kbm to start when the current Windows user signs in.

.DESCRIPTION
The task runs in the interactive user session because pynput must inject input
into that session. It deliberately does not run as SYSTEM or before sign-in.
#>
[CmdletBinding()]
param(
    [switch]$NoStart,
    [switch]$SkipDependencies,
    [switch]$NoConnectOutput
)

$ErrorActionPreference = "Stop"
$taskName = "remote-kbm"
$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherTemplate = Join-Path $PSScriptRoot "launch-background.pyw"
$sourceServerDirectory = Join-Path $projectRoot "server"
$sourceClientDirectory = Join-Path $projectRoot "client"
$requirementsPath = Join-Path $projectRoot "requirements.txt"
$startupDirectory = Join-Path $env:LOCALAPPDATA "remote-kbm"
$appDirectory = Join-Path $startupDirectory "app"
$appServerDirectory = Join-Path $appDirectory "server"
$appClientDirectory = Join-Path $appDirectory "client"
$serverPath = Join-Path $appServerDirectory "main.py"
$legacyRunnerPath = Join-Path $startupDirectory "run-at-login.ps1"
$launcherPath = Join-Path $startupDirectory "launch-background.pyw"
$logPath = Join-Path $startupDirectory "server.log"
$venvDirectory = Join-Path $startupDirectory "venv"
$pythonPath = Join-Path $venvDirectory "Scripts\python.exe"
$sitePackagesPath = Join-Path $venvDirectory "Lib\site-packages"

if (-not (Test-Path -LiteralPath $requirementsPath)) {
    throw "Requirements file not found: $requirementsPath"
}
if (-not (Test-Path -LiteralPath $launcherTemplate)) {
    throw "Windowless launcher not found: $launcherTemplate"
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceServerDirectory "main.py")) -or
    -not (Test-Path -LiteralPath (Join-Path $sourceClientDirectory "index.html"))) {
    throw "The repository is missing the server or client runtime files."
}

$pythonLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
$pythonSelector = @("-3")
if (-not $pythonLauncher) {
    $pythonLauncher = Get-Command python.exe -ErrorAction SilentlyContinue
    $pythonSelector = @()
}
if (-not $pythonLauncher) {
    throw "Windows Python was not found. Install Python 3.10 or newer first."
}

$versionCheck = 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ is required"; print(sys.version.split()[0])'
& $pythonLauncher.Source @pythonSelector -c $versionCheck | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "A supported Windows Python was not found. Install Python 3.10 or newer."
}

New-Item -ItemType Directory -Path $startupDirectory -Force | Out-Null
if (-not $SkipDependencies) {
    if (-not (Test-Path -LiteralPath $pythonPath)) {
        Write-Host "Creating isolated environment at $venvDirectory"
        & $pythonLauncher.Source @pythonSelector -m venv $venvDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the Windows Python environment."
        }
    }

    Write-Host "Installing remote-kbm dependencies..."
    & $pythonPath -m pip install --disable-pip-version-check -r $requirementsPath
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency installation failed."
    }
} elseif (-not (Test-Path -LiteralPath $pythonPath)) {
    throw "-SkipDependencies was used, but the environment does not exist: $pythonPath"
}
if (-not (Test-Path -LiteralPath $sitePackagesPath)) {
    throw "The Windows Python environment is incomplete: $sitePackagesPath"
}
$basePythonPath = & $pythonPath -c "import sys; print(sys._base_executable)"
$basePythonwPath = Join-Path (Split-Path -Parent $basePythonPath) "pythonw.exe"
if (-not (Test-Path -LiteralPath $basePythonwPath)) {
    throw "The base windowless Python executable was not found: $basePythonwPath"
}

$pythonVersion = & $pythonPath --version 2>&1
Write-Host "Using $pythonVersion from $pythonPath"
& $pythonPath -c "import aiohttp, pynput, qrcode"
if ($LASTEXITCODE -ne 0) {
    throw "The Windows Python environment failed its import check."
}

# Keep startup independent of the clone and of \\wsl$ availability.
New-Item -ItemType Directory -Path $appServerDirectory, $appClientDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $sourceServerDirectory -Filter "*.py" -File |
    Copy-Item -Destination $appServerDirectory -Force
Copy-Item -Path (Join-Path $sourceClientDirectory "*") `
    -Destination $appClientDirectory `
    -Recurse `
    -Force
Copy-Item -LiteralPath $launcherTemplate -Destination $launcherPath -Force
$sourceClientHash = (Get-FileHash `
    -LiteralPath (Join-Path $sourceClientDirectory "index.html") `
    -Algorithm SHA256).Hash
$installedClientHash = (Get-FileHash `
    -LiteralPath (Join-Path $appClientDirectory "index.html") `
    -Algorithm SHA256).Hash
if ($sourceClientHash -ne $installedClientHash) {
    throw "The installed phone client does not match the repository copy."
}
$clientBuild = $installedClientHash.Substring(0, 12).ToLowerInvariant()
Write-Host "Installed phone client build: $clientBuild"

$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$actionArguments = '-S "{0}" "{1}" "{2}" "{3}"' -f `
    $launcherPath, $sitePackagesPath, $serverPath, $logPath
$action = New-ScheduledTaskAction `
    -Execute $basePythonwPath `
    -Argument $actionArguments `
    -WorkingDirectory $appDirectory
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal `
    -UserId $userId `
    -LogonType Interactive `
    -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

$installedTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($installedTask) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $stopDeadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $stoppingListener = Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8765 `
            -ErrorAction SilentlyContinue
    } until (-not $stoppingListener -or (Get-Date) -ge $stopDeadline)
}
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Start the remote-kbm phone trackpad server for the signed-in user." `
    -Force | Out-Null
Remove-Item -LiteralPath $legacyRunnerPath -Force -ErrorAction SilentlyContinue

$existingListener = Get-NetTCPConnection -State Listen -LocalPort 8765 -ErrorAction SilentlyContinue
if ($existingListener) {
    Write-Host "Startup installed. A server is already using port 8765, so it was left running."
    Write-Host "The scheduled task will start remote-kbm automatically at your next Windows sign-in."
} elseif ($NoStart) {
    Write-Host "Startup installed. Launch skipped because -NoStart was supplied."
} else {
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 500
        $listener = Get-NetTCPConnection `
            -State Listen `
            -LocalPort 8765 `
            -ErrorAction SilentlyContinue
    } until ($listener -or (Get-Date) -ge $deadline)

    if (-not $listener) {
        $task = Get-ScheduledTask -TaskName $taskName
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Host ""
        Write-Host "remote-kbm did not start. Recent startup log:" -ForegroundColor Red
        if (Test-Path -LiteralPath $logPath) {
            Get-Content -LiteralPath $logPath -Tail 30 -Encoding UTF8 |
                ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  No startup log was created at $logPath"
        }
        throw "remote-kbm is not listening on port 8765. Task state: $($task.State); task result: $($taskInfo.LastTaskResult)."
    }

    Write-Host "Startup installed. remote-kbm is running and listening on port 8765."
}

try {
    $publicNetworks = Get-NetConnectionProfile -ErrorAction Stop |
        Where-Object { $_.NetworkCategory -eq "Public" }
    if ($publicNetworks) {
        Write-Warning "The active network is Public. On a trusted home network, change it to Private and allow Python through Windows Firewall, or phones may not connect."
    }
} catch {
    Write-Warning "Could not inspect the Windows network profile: $($_.Exception.Message)"
}

Write-Host "Task: $taskName"
Write-Host "Log:  $logPath"
Write-Host "After an update, fully close and reopen the phone app."
Write-Host "Use windows\uninstall-startup.ps1 to remove automatic startup."
if (-not $NoConnectOutput) {
    & $pythonPath $serverPath --show-connect
}
