@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT_DIR%CodexMigrationTool.ps1"
if errorlevel 1 (
  echo.
  echo Codex Migration Tool exited with an error.
  pause
)
