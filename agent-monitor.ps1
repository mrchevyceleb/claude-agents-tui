# Agent Monitor - Visual dashboard for Claude Code background agents (Windows)
# Usage: agent-monitor.ps1 [watch|status|list|kill|tail]

param(
    [Parameter(Position=0)]
    [string]$Command = "status",
    [Parameter(Position=1)]
    [string]$AgentId
)

# Fix Unicode output for Windows console
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

# Configuration - Check multiple possible locations
$PossibleAgentDirs = @(
    "$env:TEMP\claude",
    "$env:LOCALAPPDATA\claude",
    "$env:APPDATA\claude",
    "C:\tmp\claude"
)

$AGENT_DIR = $null
foreach ($dir in $PossibleAgentDirs) {
    if (Test-Path $dir) {
        $AGENT_DIR = $dir
        break
    }
}

$META_DIR = $env:TEMP
$REFRESH_RATE = 2
$STATE_FILE = "$env:TEMP\agent-monitor-state.txt"

# Colors
$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    Cyan = "Cyan"
    Magenta = "Magenta"
    White = "White"
    Gray = "DarkGray"
}

function Send-Notification {
    param([string]$Title, [string]$Message)

    # Try BurntToast if available
    if (Get-Module -ListAvailable -Name BurntToast) {
        New-BurntToastNotification -Text $Title, $Message -Sound Default
    } else {
        # Fallback to basic notification via PowerShell
        Add-Type -AssemblyName System.Windows.Forms
        $balloon = New-Object System.Windows.Forms.NotifyIcon
        $balloon.Icon = [System.Drawing.SystemIcons]::Information
        $balloon.BalloonTipIcon = "Info"
        $balloon.BalloonTipTitle = $Title
        $balloon.BalloonTipText = $Message
        $balloon.Visible = $true
        $balloon.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 100
        $balloon.Dispose()
    }
}

function Test-AgentRunning {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $lastWrite = (Get-Item $FilePath).LastWriteTime
    return ((Get-Date) - $lastWrite).TotalMinutes -lt 1
}

function Get-TaskTitle {
    param([string]$AgentId)
    $metaFile = Join-Path $META_DIR "agent-meta-$AgentId.txt"
    if (Test-Path $metaFile) {
        $content = Get-Content $metaFile -ErrorAction SilentlyContinue
        $titleLine = $content | Where-Object { $_ -match "^TITLE:" }
        if ($titleLine) {
            return ($titleLine -replace "^TITLE:\s*", "").Trim()
        }
    }
    return $null
}

function Get-StartTime {
    param([string]$AgentId)
    $metaFile = Join-Path $META_DIR "agent-meta-$AgentId.txt"
    if (Test-Path $metaFile) {
        $content = Get-Content $metaFile -ErrorAction SilentlyContinue
        $startLine = $content | Where-Object { $_ -match "^STARTED:" }
        if ($startLine) {
            return ($startLine -replace "^STARTED:\s*", "").Trim()
        }
    }
    return $null
}

function Get-ElapsedTime {
    param([string]$AgentId, [string]$OutputFile)

    $startTime = Get-StartTime -AgentId $AgentId
    if ($startTime) {
        try {
            $start = [datetime]::ParseExact($startTime, "HH:mm:ss", $null)
            $now = Get-Date
            $diff = $now - $start
            if ($diff.TotalSeconds -lt 0) { $diff = $diff.Add([timespan]::FromDays(1)) }
            return "{0}m {1:D2}s" -f [int]$diff.TotalMinutes, $diff.Seconds
        } catch { }
    }

    # Fallback to file modification time
    if (Test-Path $OutputFile) {
        $lastWrite = (Get-Item $OutputFile).LastWriteTime
        $diff = (Get-Date) - $lastWrite
        if ($diff.TotalMinutes -lt 1) {
            return "<1m"
        }
        return "{0}m" -f [int]$diff.TotalMinutes
    }
    return "-"
}

function Get-ProgressInfo {
    param([string]$OutputFile)
    if (-not (Test-Path $OutputFile)) {
        return @{ ToolCount = 0; LastTool = "-"; LastText = "" }
    }

    $content = Get-Content $OutputFile -Raw -ErrorAction SilentlyContinue
    $toolMatches = [regex]::Matches($content, '"tool_use"')
    $toolCount = $toolMatches.Count

    $lastToolMatch = [regex]::Match($content, '"name":"([^"]+)".*$', [System.Text.RegularExpressions.RegexOptions]::RightToLeft)
    $lastTool = if ($lastToolMatch.Success) { $lastToolMatch.Groups[1].Value.Substring(0, [Math]::Min(12, $lastToolMatch.Groups[1].Value.Length)) } else { "-" }

    return @{ ToolCount = $toolCount; LastTool = $lastTool }
}

function Get-ProjectName {
    param([string]$OutputFile)
    $dirPath = Split-Path (Split-Path $OutputFile -Parent) -Parent
    $folderName = Split-Path $dirPath -Leaf

    # Extract last meaningful segment
    $segments = $folderName -split '-'
    $project = $segments[-1]
    if ($project.Length -gt 12) { $project = $project.Substring(0, 12) }
    return $project
}

function Show-ProgressBar {
    param([int]$Tools, [int]$Width = 10)
    $max = 20
    $filled = [Math]::Min([int]($Tools * $Width / $max), $Width)
    $empty = $Width - $filled

    Write-Host -NoNewline -ForegroundColor Green ("$([char]0x2588)" * $filled)
    Write-Host -NoNewline -ForegroundColor DarkGray ("$([char]0x2591)" * $empty)
}

function Get-RunningAgents {
    if (-not $AGENT_DIR -or -not (Test-Path $AGENT_DIR)) { return @() }

    $running = @()
    $outputFiles = Get-ChildItem -Path $AGENT_DIR -Filter "*.output" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $outputFiles) {
        if (Test-AgentRunning -FilePath $file.FullName) {
            $running += $file.BaseName
        }
    }
    return $running
}

function Save-State {
    $running = Get-RunningAgents
    $running -join "`n" | Set-Content $STATE_FILE -Force
}

function Check-Completions {
    param([switch]$NotifyMode)

    if (-not (Test-Path $STATE_FILE)) {
        Save-State
        return
    }

    $previous = Get-Content $STATE_FILE -ErrorAction SilentlyContinue
    $current = Get-RunningAgents

    foreach ($agentId in $previous) {
        if ($agentId -and $current -notcontains $agentId) {
            $title = Get-TaskTitle -AgentId $agentId
            if ($title) {
                Send-Notification -Title "Complete" -Message $title
            } else {
                Send-Notification -Title "Complete" -Message "Agent $agentId"
            }
        }
    }

    $current -join "`n" | Set-Content $STATE_FILE -Force
}

function Show-Status {
    param([switch]$NotifyMode)

    Clear-Host

    # Header
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    if ($NotifyMode) {
        Write-Host -ForegroundColor Cyan "|" -NoNewline
        Write-Host "                 " -NoNewline
        Write-Host -ForegroundColor White "CLAUDE CODE BACKGROUND AGENTS" -NoNewline
        Write-Host "                          " -NoNewline
        Write-Host -ForegroundColor Yellow "NOTIFY ON" -NoNewline
        Write-Host "             " -NoNewline
        Write-Host -ForegroundColor Cyan "|"
    } else {
        Write-Host -ForegroundColor Cyan "|" -NoNewline
        Write-Host "                         " -NoNewline
        Write-Host -ForegroundColor White "CLAUDE CODE BACKGROUND AGENTS" -NoNewline
        Write-Host "                                            " -NoNewline
        Write-Host -ForegroundColor Cyan "|"
    }
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"

    if (-not $AGENT_DIR) {
        Write-Host -ForegroundColor Cyan "|  " -NoNewline
        Write-Host -ForegroundColor Yellow "No agent directory found. Checking: $($PossibleAgentDirs -join ', ')" -NoNewline
        Write-Host -ForegroundColor Cyan "  |"
        Write-Host -ForegroundColor Cyan "+============================================================================================================+"
        return
    }

    $agentCount = 0
    $runningCount = 0

    # Table header
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-28} " -f "TASK") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-10} " -f "PROJECT") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-8} " -f "STATUS") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-7} " -f "TIME") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-12} " -f "PROGRESS") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-14} " -f "ACTION") -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+==============================+============+==========+=========+==============+================+"

    $outputFiles = Get-ChildItem -Path $AGENT_DIR -Filter "*.output" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 6

    foreach ($file in $outputFiles) {
        $agentCount++
        $agentId = $file.BaseName

        # Get task info
        $taskTitle = Get-TaskTitle -AgentId $agentId
        if (-not $taskTitle) { $taskTitle = "$($agentId.Substring(0, [Math]::Min(10, $agentId.Length)))..." }
        if ($taskTitle.Length -gt 26) { $taskTitle = $taskTitle.Substring(0, 26) }

        # Get project name
        $projectName = Get-ProjectName -OutputFile $file.FullName
        if ($projectName.Length -gt 10) { $projectName = $projectName.Substring(0, 10) }

        # Get progress info
        $progress = Get-ProgressInfo -OutputFile $file.FullName

        # Get elapsed time
        $elapsed = Get-ElapsedTime -AgentId $agentId -OutputFile $file.FullName

        Write-Host -ForegroundColor Cyan "|" -NoNewline

        if (Test-AgentRunning -FilePath $file.FullName) {
            $runningCount++
            $spinnerChars = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
            $spinnerIndex = [int](Get-Date -UFormat %s) % 10
            $spinner = $spinnerChars[$spinnerIndex]

            Write-Host -ForegroundColor White (" {0,-26} " -f $taskTitle) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Magenta (" {0,-10} " -f $projectName) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Green (" $spinner RUN   ") -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host (" {0,-7} " -f $elapsed) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host " " -NoNewline
            Show-ProgressBar -Tools $progress.ToolCount
            Write-Host " " -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Blue (" {0,-14} " -f $progress.LastTool) -NoNewline
            Write-Host -ForegroundColor Cyan "|"
        } else {
            Write-Host -ForegroundColor DarkGray (" {0,-26} " -f $taskTitle) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-10} " -f $projectName) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Yellow (" $([char]0x2713) DONE   ") -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-7} " -f $elapsed) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host " " -NoNewline
            Show-ProgressBar -Tools $progress.ToolCount
            Write-Host " " -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-14} " -f "-") -NoNewline
            Write-Host -ForegroundColor Cyan "|"
        }
    }

    if ($agentCount -eq 0) {
        Write-Host -ForegroundColor Cyan "|" -NoNewline
        Write-Host "                                                                                                            " -NoNewline
        Write-Host -ForegroundColor Cyan "|"
        Write-Host -ForegroundColor Cyan "|        " -NoNewline
        Write-Host -ForegroundColor Yellow "No recent agents." -NoNewline
        Write-Host " Launch one with: " -NoNewline
        Write-Host -ForegroundColor White "/bga <task>" -NoNewline
        Write-Host "                                                             " -NoNewline
        Write-Host -ForegroundColor Cyan "|"
        Write-Host -ForegroundColor Cyan "|                                                                                                            |"
    }

    # Summary
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host -ForegroundColor Cyan "|  " -NoNewline
    Write-Host -ForegroundColor White "SUMMARY: " -NoNewline
    Write-Host -ForegroundColor Green "$([char]0x25CF) $runningCount running" -NoNewline
    Write-Host "   " -NoNewline
    Write-Host -ForegroundColor Yellow "$([char]0x25CB) $($agentCount - $runningCount) completed" -NoNewline
    Write-Host "   " -NoNewline
    Write-Host -ForegroundColor DarkGray "Total: $agentCount" -NoNewline
    Write-Host "                                                 " -NoNewline
    Write-Host -ForegroundColor Cyan "|"

    # Footer
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host -ForegroundColor Cyan "|  " -NoNewline
    Write-Host -ForegroundColor DarkGray "$time" -NoNewline
    Write-Host "   |   " -NoNewline
    Write-Host -ForegroundColor DarkGray "Refresh: ${REFRESH_RATE}s" -NoNewline
    Write-Host "   |   " -NoNewline
    Write-Host -ForegroundColor DarkGray "Kill: agents kill <id>" -NoNewline
    Write-Host "   |   " -NoNewline
    Write-Host -ForegroundColor DarkGray "Ctrl+C exit" -NoNewline
    Write-Host "                       " -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
}

function Watch-Agents {
    param([switch]$NotifyMode)

    if ($NotifyMode) { Save-State }

    while ($true) {
        if ($NotifyMode) { Check-Completions -NotifyMode }
        Show-Status -NotifyMode:$NotifyMode
        Start-Sleep -Seconds $REFRESH_RATE
    }
}

function Stop-Agent {
    param([string]$AgentId)

    if (-not $AgentId) {
        Write-Host -ForegroundColor White "Usage:" -NoNewline
        Write-Host " agents kill <agent_id>"
        Write-Host ""
        Show-AgentList
        return
    }

    $processes = Get-Process | Where-Object { $_.CommandLine -like "*$AgentId*" } -ErrorAction SilentlyContinue

    if ($processes) {
        Write-Host -ForegroundColor Yellow "Killing agent $AgentId..."
        $processes | Stop-Process -Force

        $metaFile = Join-Path $META_DIR "agent-meta-$AgentId.txt"
        if (Test-Path $metaFile) {
            Add-Content -Path $metaFile -Value "STATUS: KILLED"
        }

        Write-Host -ForegroundColor Green "$([char]0x2713) Agent killed"
    } else {
        Write-Host -ForegroundColor Yellow "No running process found for agent $AgentId"
        Write-Host "It may have already completed."
    }
}

function Show-AgentList {
    Write-Host -ForegroundColor White "Background Agents (last 60 min):"
    Write-Host ""

    if (-not $AGENT_DIR -or -not (Test-Path $AGENT_DIR)) {
        Write-Host "  No agent directory found"
        return
    }

    $found = 0
    $running = 0

    $outputFiles = Get-ChildItem -Path $AGENT_DIR -Filter "*.output" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { (Get-Date) - $_.LastWriteTime -lt [timespan]::FromMinutes(60) } |
        Sort-Object LastWriteTime -Descending

    foreach ($file in $outputFiles) {
        $found++
        $agentId = $file.BaseName
        $taskTitle = Get-TaskTitle -AgentId $agentId
        $elapsed = Get-ElapsedTime -AgentId $agentId -OutputFile $file.FullName

        if (Test-AgentRunning -FilePath $file.FullName) {
            $running++
            if ($taskTitle) {
                Write-Host -ForegroundColor Green "  $([char]0x25CF)" -NoNewline
                Write-Host -ForegroundColor White " $taskTitle" -NoNewline
                Write-Host -ForegroundColor DarkGray " ($agentId)" -NoNewline
                Write-Host " - $elapsed"
            } else {
                Write-Host -ForegroundColor Green "  $([char]0x25CF) $agentId - $elapsed"
            }
        } else {
            if ($taskTitle) {
                Write-Host -ForegroundColor Yellow "  $([char]0x25CB)" -NoNewline
                Write-Host " $taskTitle" -NoNewline
                Write-Host -ForegroundColor DarkGray " ($agentId)"
            } else {
                Write-Host -ForegroundColor Yellow "  $([char]0x25CB) $agentId"
            }
        }
    }

    if ($found -eq 0) {
        Write-Host "  No recent agents"
    } else {
        Write-Host ""
        Write-Host -ForegroundColor Green "  $([char]0x25CF)" -NoNewline
        Write-Host " = running  " -NoNewline
        Write-Host -ForegroundColor Yellow "$([char]0x25CB)" -NoNewline
        Write-Host " = done"
        Write-Host "  Total: $found ($running running)"
    }
}

function Show-AgentTail {
    param([string]$AgentId)

    if (-not $AgentId) {
        Write-Host "Usage: agents tail <agent_id>"
        return
    }

    if (-not $AGENT_DIR) {
        Write-Host "No agent directory found"
        return
    }

    $outputFile = Get-ChildItem -Path $AGENT_DIR -Filter "$AgentId*.output" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($outputFile) {
        $taskTitle = Get-TaskTitle -AgentId $AgentId
        if ($taskTitle) {
            Write-Host -ForegroundColor White "Agent: $taskTitle"
        } else {
            Write-Host -ForegroundColor White "Agent: $AgentId"
        }
        Write-Host -ForegroundColor Cyan ("-" * 55)
        Get-Content $outputFile.FullName -Tail 50 -Wait
    } else {
        Write-Host "Agent not found: $AgentId"
        Write-Host "Try: agents list"
    }
}

function Show-Help {
    Write-Host -ForegroundColor White "Agent Monitor" -NoNewline
    Write-Host " - Dashboard for Claude Code background agents"
    Write-Host ""
    Write-Host "Usage: agents [command]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host -ForegroundColor White "  n              " -NoNewline
    Write-Host "Watch + notifications (recommended)"
    Write-Host -ForegroundColor White "  status         " -NoNewline
    Write-Host "Show current status"
    Write-Host -ForegroundColor White "  list           " -NoNewline
    Write-Host "List all recent agents"
    Write-Host -ForegroundColor White "  tail <id>      " -NoNewline
    Write-Host "Follow agent output"
    Write-Host -ForegroundColor White "  kill <id>      " -NoNewline
    Write-Host "Kill a running agent"
    Write-Host -ForegroundColor White "  help           " -NoNewline
    Write-Host "Show this help"
}

# Main
switch ($Command.ToLower()) {
    { $_ -in "n", "wn", "notify" } { Watch-Agents -NotifyMode }
    "watch" { Watch-Agents }
    { $_ -in "status", "s" } { Show-Status }
    { $_ -in "list", "l" } { Show-AgentList }
    { $_ -in "tail", "t" } { Show-AgentTail -AgentId $AgentId }
    { $_ -in "kill", "k" } { Stop-Agent -AgentId $AgentId }
    default { Show-Help }
}
