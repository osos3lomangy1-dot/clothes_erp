@echo off
chcp 65001 >nul
echo ========================================================
echo  تحميل حزمة Microsoft Visual C++ Redistributable (x64)
echo ========================================================
echo.
echo جاري تحميل vc_redist.x64.exe لوضعها داخل مجلد التثبيت...

curl.exe -L -o "%~dp0vc_redist.x64.exe" https://aka.ms/vs/17/release/vc_redist.x64.exe

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [نجاح] تم تحميل vc_redist.x64.exe بنجاح!
    echo الآن عند تجميع ملف Inno Setup عبر أمر:
    echo   iscc inno_setup.iss
    echo سيتم تضمين الحزمة داخل ملف التثبيت Setup.exe ليعمل بدون إنترنت تماماً.
) else (
    echo.
    echo [خطأ] فشل التحميل. يرجى التحقق من اتصال الإنترنت.
)
echo.
pause

