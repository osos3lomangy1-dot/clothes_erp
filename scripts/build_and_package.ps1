#!/usr/bin/env pwsh
# build_and_package.ps1 — Build and package Windows release locally
# Usage: .\scripts\build_and_package.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== Orchid ERP - Windows Build Script ===" -ForegroundColor Cyan

# 1. Analyze
Write-Host "`n[1/5] Running flutter analyze..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) { Write-Host "❌ Analyze failed" -ForegroundColor Red; exit 1 }
Write-Host "✅ Analyze passed" -ForegroundColor Green

# 2. Test
Write-Host "`n[2/5] Running flutter test..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) { Write-Host "❌ Tests failed" -ForegroundColor Red; exit 1 }
Write-Host "✅ Tests passed" -ForegroundColor Green

# 3. Build Windows Release
Write-Host "`n[3/5] Building Windows release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Write-Host "❌ Build failed" -ForegroundColor Red; exit 1 }
Write-Host "✅ Build passed" -ForegroundColor Green

# 4. Get version from pubspec.yaml
$version = (Select-String -Path pubspec.yaml -Pattern "^version:\s+(.+)\+").Matches.Groups[1].Value.Trim()
if (-not $version) { $version = "1.0.0" }
Write-Host "`n[4/5] Packaging version: $version" -ForegroundColor Yellow

$releaseDir = "build\windows\x64\runner\Release"
$zipName = "orchid_erp_windows_v${version}.zip"

if (Test-Path $zipName) { Remove-Item $zipName -Force }
Compress-Archive -Path "$releaseDir\*" -DestinationPath $zipName -Force
Write-Host "✅ ZIP created: $zipName" -ForegroundColor Green

# 5. Build MSIX (optional)
Write-Host "`n[5/5] Building MSIX installer..." -ForegroundColor Yellow
dart run msix:create
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ MSIX created in $releaseDir" -ForegroundColor Green
} else {
    Write-Host "⚠️  MSIX build skipped (non-fatal)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✅ BUILD COMPLETE!" -ForegroundColor Green
Write-Host "   ZIP:  $zipName"
Write-Host "   MSIX: $releaseDir\clothes_erp.msix"
Write-Host "========================================" -ForegroundColor Cyan

