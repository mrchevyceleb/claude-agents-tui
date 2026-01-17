# Claude Agents TUI - Windows Installer
# Installs the background agent dashboard and /bga skill

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Agents TUI - Windows Install  " -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create directories
$scriptsDir = "$env:USERPROFILE\.claude\scripts"
$commandsDir = "$env:USERPROFILE\.claude\commands"

Write-Host "[1/5] Creating directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
New-Item -ItemType Directory -Path $commandsDir -Force | Out-Null
Write-Host "      Created: $scriptsDir" -ForegroundColor Green
Write-Host "      Created: $commandsDir" -ForegroundColor Green

# Copy files
Write-Host ""
Write-Host "[2/5] Copying files..." -ForegroundColor Yellow
Copy-Item "agent-monitor.ps1" "$scriptsDir\agent-monitor.ps1" -Force
Write-Host "      Copied: agent-monitor.ps1" -ForegroundColor Green
Copy-Item "agents.cmd" "$scriptsDir\agents.cmd" -Force
Write-Host "      Copied: agents.cmd" -ForegroundColor Green
Copy-Item "bga.md" "$commandsDir\bga.md" -Force
Write-Host "      Copied: bga.md (skill)" -ForegroundColor Green

# Add to PATH
Write-Host ""
Write-Host "[3/5] Adding to PATH..." -ForegroundColor Yellow
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($currentPath -notlike "*$scriptsDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$scriptsDir", 'User')
    Write-Host "      Added $scriptsDir to PATH" -ForegroundColor Green
    Write-Host "      NOTE: Restart your terminal for PATH changes to take effect" -ForegroundColor Yellow
} else {
    Write-Host "      Already in PATH" -ForegroundColor Green
}

# Check for BurntToast (optional notification module)
Write-Host ""
Write-Host "[4/5] Checking for BurntToast (optional)..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name BurntToast) {
    Write-Host "      BurntToast already installed" -ForegroundColor Green
} else {
    Write-Host "      BurntToast not installed (notifications will use basic balloons)" -ForegroundColor DarkGray
    Write-Host "      Install with: Install-Module -Name BurntToast -Scope CurrentUser" -ForegroundColor DarkGray
}

# Done
Write-Host ""
Write-Host "[5/5] Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Next Steps:" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Restart your terminal (for PATH changes)" -ForegroundColor White
Write-Host "  2. Run: " -NoNewline -ForegroundColor White
Write-Host "agents" -ForegroundColor Green
Write-Host "  3. Launch agents with: " -NoNewline -ForegroundColor White
Write-Host "/bga <task>" -ForegroundColor Green
Write-Host ""
Write-Host "  Examples:" -ForegroundColor DarkGray
Write-Host "    /bga research the top 5 AI coding tools" -ForegroundColor DarkGray
Write-Host "    /bga refactor the auth system" -ForegroundColor DarkGray
Write-Host "    /bga run comprehensive tests" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Dashboard shortcuts:" -ForegroundColor DarkGray
Write-Host "    N     - Toggle notifications" -ForegroundColor DarkGray
Write-Host "    1-9   - Quick view agent output" -ForegroundColor DarkGray
Write-Host "    D+1-9 - Show agent details" -ForegroundColor DarkGray
Write-Host "    R/F/A - Filter running/finished/all" -ForegroundColor DarkGray
Write-Host "    Q     - Quit" -ForegroundColor DarkGray
Write-Host ""
Write-Host "For more info: " -NoNewline -ForegroundColor White
Write-Host "https://github.com/mrchevyceleb/claude-agents-tui" -ForegroundColor Cyan
Write-Host ""
