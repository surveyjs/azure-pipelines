@echo off
pushd "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "sync-pipes.ps1" -TargetBranch V3
pause