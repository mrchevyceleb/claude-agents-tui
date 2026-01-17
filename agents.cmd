@echo off
REM Agent Monitor - Launcher for Claude Code background agent dashboard
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\scripts\agent-monitor.ps1" %*
