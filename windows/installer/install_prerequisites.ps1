<#
.SYNOPSIS
    Automated Visual C++ Redistributable 2015-2022 (x64) Installer and App Launcher
.DESCRIPTION
    Checks if Microsoft Visual C++ 2015-2022 (x64) is installed.
    If missing, downloads it from the official Microsoft endpoint and installs it silently.
    Then launches the Flutter executable.
#>

$ErrorActionPreference = 'Stop'

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Orkeed Clothes ERP - Prerequisites & Launcher" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

function Test-VCRedistInstalled {
    $regPath = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    if (Test-Path $regPath) {
        $val = (Get-ItemProperty -Path $regPath -Name "Installed" -ErrorAction SilentlyContinue).Installed
        if ($val -eq 1) { return $true }
    }

    $sys32Dll = Join-Path $env:SystemRoot "System32\msvcp140.dll"
    if (Test-Path $sys32Dll) {
        return $true
    }

    return $false
}

if (-not (Test-VCRedistInstalled)) {
    Write-Host "`n[!] Microsoft Visual C++ Redistributable (x64) is not installed." -ForegroundColor Yellow
    Write-Host "[*] Downloading official installer from Microsoft..." -ForegroundColor Yellow

    $vcUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $tempFile = Join-Path $env:TEMP "vc_redist.x64.exe"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $vcUrl -OutFile $tempFile -UseBasicParsing
        Write-Host "[*] Installing VC++ Redistributable silently..." -ForegroundColor Cyan
        $process = Start-Process -FilePath $tempFile -ArgumentList "/install /quiet /norestart" -Wait -PassThru
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        Write-Host "[✓] VC++ Redistributable installed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "[X] Failed to download or install automatically: $_" -ForegroundColor Red
        Write-Host "Please download and install manually: $vcUrl" -ForegroundColor White
    }
} else {
    Write-Host "[✓] Visual C++ Runtime (MSVCP140.dll) is already installed." -ForegroundColor Green
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appExe = Join-Path $scriptDir "clothes_erp.exe"

if (-not (Test-Path $appExe)) {
    $appExe = Join-Path $scriptDir "Release\clothes_erp.exe"
}

if (Test-Path $appExe) {
    Write-Host "[*] Launching Orkeed Clothes ERP..." -ForegroundColor Cyan
    Start-Process -FilePath $appExe
} else {
    Write-Host "[!] Could not find clothes_erp.exe in $scriptDir" -ForegroundColor Yellow
}

