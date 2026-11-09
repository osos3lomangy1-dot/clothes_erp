@echo off
chcp 65001 >nul
title Orkeed Clothes ERP - فحص متطلبات التشغيل

:: -------------------------------------------------------------
:: هذا السكريبت يتحقق من وجود حزمة Microsoft Visual C++ Runtime
:: ويقوم بتثبيتها تلقائياً في حال عدم وجودها لمنع خطأ MSVCP140.dll
:: ثم يقوم بتشغيل البرنامج مباشرة.
:: -------------------------------------------------------------

set "APP_DIR=%~dp0"
set "EXE_NAME=clothes_erp.exe"

:: 1. التحقق من وجود ملفات VC++ Runtime (MSVCP140.dll)
reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" /v Installed 2>nul | findstr /i "0x1" >nul
if %ERRORLEVEL% EQU 0 goto :RUN_APP

if exist "%SystemRoot%\System32\msvcp140.dll" (
    if exist "%SystemRoot%\System32\vcruntime140.dll" goto :RUN_APP
)

:: 2. الحزمة مفقودة -> إبلاغ المستخدم وتحميلها
echo ==============================================================================
echo  تنبيه: حزمة Microsoft Visual C++ Redistributable (x64) غير مثبتة على هذا الجهاز.
echo  جاري تحميل وتثبيت الحزمة تلقائياً لمنع حدوث أي أخطاء (MSVCP140.dll)...
echo ==============================================================================
echo.

set "VC_TEMP=%TEMP%\vc_redist.x64.exe"

echo ⏳ جاري التحميل من مايكروسوفت مباشرة...
curl.exe -L -s -o "%VC_TEMP%" https://aka.ms/vs/17/release/vc_redist.x64.exe

if not exist "%VC_TEMP%" (
    echo [تحذير] تعذر تحميل الحزمة عبر curl. جاري المحاولة عبر PowerShell...
    powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('https://aka.ms/vs/17/release/vc_redist.x64.exe', '%VC_TEMP%')"
)

if not exist "%VC_TEMP%" (
    echo [خطأ] تعذر تحميل حزمة Visual C++. يرجى تحميلها يدوياً من الرابط:
    echo https://aka.ms/vs/17/release/vc_redist.x64.exe
    pause
    goto :RUN_APP
)

echo 🔧 جاري تثبيت الحزمة بهدوء (Silent Installation)...
start /wait "" "%VC_TEMP%" /install /quiet /norestart
del /f /q "%VC_TEMP%" 2>nul

echo [نجاح] اكتمل تثبيت متطلبات التشغيل بنجاح!
echo.

:RUN_APP
:: 3. تشغيل برنامج أوركيد لإدارة الملابس
if exist "%APP_DIR%%EXE_NAME%" (
    start "" "%APP_DIR%%EXE_NAME%"
) else if exist "%APP_DIR%Release\%EXE_NAME%" (
    start "" "%APP_DIR%Release\%EXE_NAME%"
) else (
    echo [خطأ] لم يتم العثور على ملف البرنامج (%EXE_NAME%) في المسار الحالي.
    pause
)

