@echo off
chcp 65001 >nul
setlocal

set "APP_DIR=%~dp0"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $lnk = $ws.CreateShortcut((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\독케익시청자용v1.8.32.lnk')); $lnk.TargetPath = (Join-Path '%APP_DIR%' 'AutoHotkey64.exe'); $lnk.Arguments = '""' + (Join-Path '%APP_DIR%' 'dogcake_proviewer_v1.8.32.ahk') + '""'; $lnk.WorkingDirectory = '%APP_DIR%'; $lnk.IconLocation = (Join-Path '%APP_DIR%' 'dogicon.ico'); $lnk.Save()"

echo.
echo 시작프로그램 등록 완료!
echo.
pause