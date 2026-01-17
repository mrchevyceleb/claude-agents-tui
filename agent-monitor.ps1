# Agent Monitor - Visual dashboard for Claude Code background agents (Windows)
# Usage: agent-monitor.ps1 [watch|status|list|kill|tail]
# Version: 2.0 - Enhanced with 10 new features

param(
    [Parameter(Position=0)]
    [string]$Command = "watch",
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
$script:REFRESH_RATE = 2
$STATE_FILE = "$env:TEMP\agent-monitor-state.txt"
$COMPLETION_FILE = "$env:TEMP\agent-completions.txt"

# View state
$script:FilterMode = "ALL"  # ALL, RUNNING, FINISHED
$script:CurrentPage = 0
$script:PageSize = 10
$script:CachedFiles = @()
$script:QuickViewIndex = -1
$script:StatusMessage = ""
$script:StatusMessageTime = $null

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
    param([string]$Title, [string]$Message, [string]$Status = "SUCCESS")

    # Play sound
    try {
        Add-Type -AssemblyName System.Media -ErrorAction SilentlyContinue
        if ($Status -eq "FAILED") {
            [System.Media.SystemSounds]::Hand.Play()
        } else {
            [System.Media.SystemSounds]::Asterisk.Play()
        }
    } catch { }

    # Try BurntToast if available
    if (Get-Module -ListAvailable -Name BurntToast) {
        New-BurntToastNotification -Text $Title, $Message -Sound Default
    } else {
        # Fallback to basic notification via PowerShell
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $balloon = New-Object System.Windows.Forms.NotifyIcon
            $balloon.Icon = [System.Drawing.SystemIcons]::Information
            $balloon.BalloonTipIcon = if ($Status -eq "FAILED") { "Error" } else { "Info" }
            $balloon.BalloonTipTitle = $Title
            $balloon.BalloonTipText = $Message
            $balloon.Visible = $true
            $balloon.ShowBalloonTip(5000)
            Start-Sleep -Milliseconds 100
            $balloon.Dispose()
        } catch { }
    }
}

function Test-AgentRunning {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $false }
    $lastWrite = (Get-Item $FilePath).LastWriteTime
    return ((Get-Date) - $lastWrite).TotalMinutes -lt 1
}

function Get-TaskTitle {
    param([string]$AgentId, [string]$OutputFile = $null)

    # First try metadata file
    $metaFile = Join-Path $META_DIR "agent-meta-$AgentId.txt"
    if (Test-Path $metaFile) {
        $content = Get-Content $metaFile -ErrorAction SilentlyContinue
        $titleLine = $content | Where-Object { $_ -match "^TITLE:" }
        if ($titleLine) {
            return ($titleLine -replace "^TITLE:\s*", "").Trim()
        }
    }

    # Fallback: extract from project folder path
    if ($OutputFile -and (Test-Path $OutputFile)) {
        $projectPath = Split-Path (Split-Path $OutputFile -Parent) -Parent
        $folderName = Split-Path $projectPath -Leaf

        # Clean up folder name: C--KG-APPS-r-link-live -> r-link-live
        $cleanName = $folderName -replace '^C--', '' -replace '^[A-Z]--', ''
        $segments = $cleanName -split '-'

        # Get last meaningful segment (project name)
        $projectName = $segments[-1]
        if ($projectName.Length -gt 2) {
            return "$projectName task"
        }

        # Try second to last if last is too short
        if ($segments.Length -gt 1) {
            $projectName = $segments[-2..-1] -join "-"
            return "$projectName task"
        }
    }

    return $null
}

function Get-AgentStatus {
    param([string]$OutputFile, [string]$AgentId)

    # Check if killed
    $metaFile = Join-Path $META_DIR "agent-meta-$AgentId.txt"
    if (Test-Path $metaFile) {
        $content = Get-Content $metaFile -Raw -ErrorAction SilentlyContinue
        if ($content -match "STATUS:\s*KILLED") {
            return "KILLED"
        }
    }

    # Check for errors in output (last 100 lines)
    if (Test-Path $OutputFile) {
        $tail = Get-Content $OutputFile -Tail 100 -ErrorAction SilentlyContinue
        if ($tail) {
            $tailText = $tail -join "`n"
            # Look for error patterns (but not in strings like "error handling" documentation)
            if ($tailText -match "(?i)(^|\s)(error:|exception:|fatal:|failed to|cannot |Error\s*\[|FAILED)") {
                return "FAILED"
            }
        }
    }

    return "SUCCESS"
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

function Get-CompletionTime {
    param([string]$AgentId)

    if (Test-Path $COMPLETION_FILE) {
        $completions = Get-Content $COMPLETION_FILE -ErrorAction SilentlyContinue
        foreach ($line in $completions) {
            if ($line -match "^$AgentId\|(.+)$") {
                return $Matches[1]
            }
        }
    }
    return $null
}

function Save-CompletionTime {
    param([string]$AgentId, [string]$Duration)

    "$AgentId|$Duration" | Add-Content -Path $COMPLETION_FILE -ErrorAction SilentlyContinue
}

function Get-ElapsedTime {
    param([string]$AgentId, [string]$OutputFile, [switch]$IsRunning)

    # For completed agents, try to get stored completion time
    if (-not $IsRunning) {
        $completionTime = Get-CompletionTime -AgentId $AgentId
        if ($completionTime) {
            return $completionTime
        }
    }

    $startTime = Get-StartTime -AgentId $AgentId
    if ($startTime) {
        try {
            $start = [datetime]::ParseExact($startTime, "HH:mm:ss", $null)
            $now = Get-Date
            $diff = $now - $start
            if ($diff.TotalSeconds -lt 0) { $diff = $diff.Add([timespan]::FromDays(1)) }

            if ($IsRunning) {
                return "{0}m {1:D2}s" -f [int]$diff.TotalMinutes, $diff.Seconds
            } else {
                # Store completion time for future reference
                $duration = "{0}m {1:D2}s" -f [int]$diff.TotalMinutes, $diff.Seconds
                Save-CompletionTime -AgentId $AgentId -Duration $duration
                return $duration
            }
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
    if (-not $content) {
        return @{ ToolCount = 0; LastTool = "-"; LastText = "" }
    }

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
            # Find the output file to check status
            $outputFile = Get-ChildItem -Path $AGENT_DIR -Filter "$agentId.output" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            $status = if ($outputFile) { Get-AgentStatus -OutputFile $outputFile.FullName -AgentId $agentId } else { "SUCCESS" }

            $title = Get-TaskTitle -AgentId $agentId -OutputFile $outputFile.FullName
            $statusIcon = if ($status -eq "FAILED") { "FAILED" } else { "Complete" }

            if ($title) {
                Send-Notification -Title $statusIcon -Message $title -Status $status
            } else {
                Send-Notification -Title $statusIcon -Message "Agent $agentId" -Status $status
            }
        }
    }

    $current -join "`n" | Set-Content $STATE_FILE -Force
}

function Set-StatusMessage {
    param([string]$Message)
    $script:StatusMessage = $Message
    $script:StatusMessageTime = Get-Date
}

function Show-QuickView {
    param([int]$Index)

    if ($Index -lt 0 -or $Index -ge $script:CachedFiles.Count) { return }

    $file = $script:CachedFiles[$Index]
    Clear-Host

    $taskTitle = Get-TaskTitle -AgentId $file.BaseName -OutputFile $file.FullName
    if (-not $taskTitle) { $taskTitle = $file.BaseName }

    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host -ForegroundColor White "  QUICK VIEW: $taskTitle" -NoNewline
    Write-Host (" " * (90 - $taskTitle.Length)) -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host -ForegroundColor DarkGray "  Press any key to return..."
    Write-Host -ForegroundColor Cyan ("=" * 108)
    Write-Host ""

    if (Test-Path $file.FullName) {
        $lines = Get-Content $file.FullName -Tail 15 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            $displayLine = if ($line.Length -gt 105) { $line.Substring(0, 102) + "..." } else { $line }
            Write-Host "  $displayLine"
        }
    }

    Write-Host ""
    Write-Host -ForegroundColor Cyan ("=" * 108)

    [Console]::ReadKey($true) | Out-Null
}

function Show-AgentDetails {
    param([int]$Index)

    if ($Index -lt 0 -or $Index -ge $script:CachedFiles.Count) { return }

    $file = $script:CachedFiles[$Index]
    $agentId = $file.BaseName
    $isRunning = Test-AgentRunning -FilePath $file.FullName

    Clear-Host

    $taskTitle = Get-TaskTitle -AgentId $agentId -OutputFile $file.FullName
    if (-not $taskTitle) { $taskTitle = "Unknown Task" }

    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host -ForegroundColor White "  AGENT DETAILS" -NoNewline
    Write-Host (" " * 89) -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host ""

    # Basic info
    Write-Host -ForegroundColor White "  Task:      " -NoNewline
    Write-Host $taskTitle
    Write-Host -ForegroundColor White "  Agent ID:  " -NoNewline
    Write-Host $agentId
    Write-Host -ForegroundColor White "  Project:   " -NoNewline
    Write-Host (Get-ProjectName -OutputFile $file.FullName)
    Write-Host -ForegroundColor White "  Status:    " -NoNewline
    if ($isRunning) {
        Write-Host -ForegroundColor Green "RUNNING"
    } else {
        $status = Get-AgentStatus -OutputFile $file.FullName -AgentId $agentId
        switch ($status) {
            "SUCCESS" { Write-Host -ForegroundColor Green "SUCCESS" }
            "FAILED" { Write-Host -ForegroundColor Red "FAILED" }
            "KILLED" { Write-Host -ForegroundColor Yellow "KILLED" }
        }
    }

    # Time info
    $startTime = Get-StartTime -AgentId $agentId
    Write-Host -ForegroundColor White "  Started:   " -NoNewline
    Write-Host $(if ($startTime) { $startTime } else { "Unknown" })
    Write-Host -ForegroundColor White "  Duration:  " -NoNewline
    Write-Host (Get-ElapsedTime -AgentId $agentId -OutputFile $file.FullName -IsRunning:$isRunning)

    # Progress info
    $progress = Get-ProgressInfo -OutputFile $file.FullName
    Write-Host -ForegroundColor White "  Tools:     " -NoNewline
    Write-Host "$($progress.ToolCount) tool calls"
    Write-Host -ForegroundColor White "  Last Tool: " -NoNewline
    Write-Host $progress.LastTool

    # Output file
    Write-Host ""
    Write-Host -ForegroundColor White "  Output:    " -NoNewline
    Write-Host $file.FullName

    Write-Host ""
    Write-Host -ForegroundColor Cyan ("=" * 108)
    Write-Host -ForegroundColor DarkGray "  Press any key to return, C to copy agent ID..."

    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'C') {
        Set-Clipboard -Value $agentId
        Set-StatusMessage "Copied: $agentId"
    }
}

function Show-Status {
    param(
        [switch]$NotifyMode,
        [string]$FilterMode = "ALL",
        [int]$Page = 0
    )

    Clear-Host

    # Header
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host "                              " -NoNewline
    Write-Host -ForegroundColor White "CLAUDE CODE BACKGROUND AGENTS" -NoNewline
    Write-Host "                               " -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+------------------------------------------------------------------------------------------------------------+"

    # Keyboard shortcuts bar - Line 1
    Write-Host -ForegroundColor Cyan "|  " -NoNewline
    Write-Host -ForegroundColor White "[N]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Notify: " -NoNewline
    if ($NotifyMode) {
        Write-Host -ForegroundColor Green "ON " -NoNewline
    } else {
        Write-Host -ForegroundColor DarkGray "OFF" -NoNewline
    }
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor White "[R/F/A]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Filter: " -NoNewline
    switch ($FilterMode) {
        "RUNNING" { Write-Host -ForegroundColor Green "RUN" -NoNewline }
        "FINISHED" { Write-Host -ForegroundColor Yellow "FIN" -NoNewline }
        default { Write-Host -ForegroundColor White "ALL" -NoNewline }
    }
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor White "[+/-]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Speed: " -NoNewline
    Write-Host -ForegroundColor White "${script:REFRESH_RATE}s" -NoNewline
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor White "[C]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Copy" -NoNewline
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor White "[Q]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Quit" -NoNewline
    Write-Host "               " -NoNewline
    Write-Host -ForegroundColor Cyan "|"

    # Keyboard shortcuts bar - Line 2
    Write-Host -ForegroundColor Cyan "|  " -NoNewline
    Write-Host -ForegroundColor White "[1-9]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Quick view" -NoNewline
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor White "[D]+[1-9]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Details" -NoNewline
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor White "[PgUp/PgDn]" -NoNewline
    Write-Host -ForegroundColor DarkGray " Page" -NoNewline

    # Status message (if recent)
    if ($script:StatusMessage -and $script:StatusMessageTime -and ((Get-Date) - $script:StatusMessageTime).TotalSeconds -lt 3) {
        Write-Host "                  " -NoNewline
        Write-Host -ForegroundColor Green $script:StatusMessage -NoNewline
        Write-Host "      " -NoNewline
    } else {
        Write-Host "                                            " -NoNewline
        $script:StatusMessage = ""
    }
    Write-Host -ForegroundColor Cyan "|"

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
    $successCount = 0
    $failedCount = 0

    # Table header
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host -ForegroundColor DarkGray " # " -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-26} " -f "TASK") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-10} " -f "PROJECT") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-10} " -f "STATUS") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-9} " -f "TIME") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-12} " -f "PROGRESS") -NoNewline
    Write-Host -ForegroundColor Cyan "|" -NoNewline
    Write-Host (" {0,-12} " -f "ACTION") -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+===+============================+============+============+===========+==============+==============+"

    # Get all output files
    $allFiles = Get-ChildItem -Path $AGENT_DIR -Filter "*.output" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    # Apply filter
    $filteredFiles = switch ($FilterMode) {
        "RUNNING" { $allFiles | Where-Object { Test-AgentRunning -FilePath $_.FullName } }
        "FINISHED" { $allFiles | Where-Object { -not (Test-AgentRunning -FilePath $_.FullName) } }
        default { $allFiles }
    }

    # Calculate pagination
    $totalPages = [Math]::Ceiling($filteredFiles.Count / $script:PageSize)
    if ($totalPages -eq 0) { $totalPages = 1 }
    if ($Page -ge $totalPages) { $Page = $totalPages - 1 }
    if ($Page -lt 0) { $Page = 0 }

    $startIndex = $Page * $script:PageSize
    $pageFiles = $filteredFiles | Select-Object -Skip $startIndex -First $script:PageSize

    # Cache for quick view
    $script:CachedFiles = @($pageFiles)

    $displayIndex = 0
    foreach ($file in $pageFiles) {
        $displayIndex++
        $agentCount++
        $agentId = $file.BaseName
        $isRunning = Test-AgentRunning -FilePath $file.FullName

        # Get task info
        $taskTitle = Get-TaskTitle -AgentId $agentId -OutputFile $file.FullName
        if (-not $taskTitle) { $taskTitle = "$($agentId.Substring(0, [Math]::Min(10, $agentId.Length)))..." }
        if ($taskTitle.Length -gt 24) { $taskTitle = $taskTitle.Substring(0, 24) }

        # Get project name
        $projectName = Get-ProjectName -OutputFile $file.FullName
        if ($projectName.Length -gt 10) { $projectName = $projectName.Substring(0, 10) }

        # Get progress info
        $progress = Get-ProgressInfo -OutputFile $file.FullName

        # Get elapsed time
        $elapsed = Get-ElapsedTime -AgentId $agentId -OutputFile $file.FullName -IsRunning:$isRunning
        if ($elapsed.Length -gt 9) { $elapsed = $elapsed.Substring(0, 9) }

        Write-Host -ForegroundColor Cyan "|" -NoNewline

        if ($isRunning) {
            $runningCount++
            $spinnerChars = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
            $spinnerIndex = [int](Get-Date -UFormat %s) % 10
            $spinner = $spinnerChars[$spinnerIndex]

            Write-Host -ForegroundColor DarkGray (" {0} " -f $displayIndex) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor White (" {0,-24} " -f $taskTitle) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Magenta (" {0,-10} " -f $projectName) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Green (" $spinner RUNNING ") -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host (" {0,-9} " -f $elapsed) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host " " -NoNewline
            Show-ProgressBar -Tools $progress.ToolCount
            Write-Host " " -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor Blue (" {0,-12} " -f $progress.LastTool) -NoNewline
            Write-Host -ForegroundColor Cyan "|"
        } else {
            $status = Get-AgentStatus -OutputFile $file.FullName -AgentId $agentId

            switch ($status) {
                "SUCCESS" {
                    $successCount++
                    $statusDisplay = "$([char]0x2713) SUCCESS"
                    $statusColor = "Green"
                }
                "FAILED" {
                    $failedCount++
                    $statusDisplay = "$([char]0x2717) FAILED "
                    $statusColor = "Red"
                }
                "KILLED" {
                    $failedCount++
                    $statusDisplay = "$([char]0x26A0) KILLED "
                    $statusColor = "Yellow"
                }
            }

            Write-Host -ForegroundColor DarkGray (" {0} " -f $displayIndex) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-24} " -f $taskTitle) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-10} " -f $projectName) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor $statusColor (" $statusDisplay ") -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-9} " -f $elapsed) -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host " " -NoNewline
            Show-ProgressBar -Tools $progress.ToolCount
            Write-Host " " -NoNewline
            Write-Host -ForegroundColor Cyan "|" -NoNewline
            Write-Host -ForegroundColor DarkGray (" {0,-12} " -f "-") -NoNewline
            Write-Host -ForegroundColor Cyan "|"
        }
    }

    if ($agentCount -eq 0) {
        Write-Host -ForegroundColor Cyan "|" -NoNewline
        Write-Host "                                                                                                            " -NoNewline
        Write-Host -ForegroundColor Cyan "|"
        Write-Host -ForegroundColor Cyan "|        " -NoNewline
        Write-Host -ForegroundColor Yellow "No agents found." -NoNewline
        Write-Host " Launch one with: " -NoNewline
        Write-Host -ForegroundColor White "/bga <task>" -NoNewline
        Write-Host "                                                              " -NoNewline
        Write-Host -ForegroundColor Cyan "|"
        Write-Host -ForegroundColor Cyan "|                                                                                                            |"
    }

    # Count totals from all files (not just current page)
    $totalRunning = ($allFiles | Where-Object { Test-AgentRunning -FilePath $_.FullName }).Count
    $totalFinished = $allFiles.Count - $totalRunning

    # Summary with success rate
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    Write-Host -ForegroundColor Cyan "|  " -NoNewline
    Write-Host -ForegroundColor White "SUMMARY: " -NoNewline
    Write-Host -ForegroundColor Green "$([char]0x25CF) $totalRunning running" -NoNewline
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor Yellow "$([char]0x25CB) $totalFinished done" -NoNewline
    if ($successCount -gt 0 -or $failedCount -gt 0) {
        Write-Host " (" -NoNewline
        Write-Host -ForegroundColor Green "$successCount$([char]0x2713)" -NoNewline
        Write-Host " " -NoNewline
        Write-Host -ForegroundColor Red "$failedCount$([char]0x2717)" -NoNewline
        Write-Host ")" -NoNewline
    }
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor DarkGray "Total: $($allFiles.Count)" -NoNewline
    Write-Host "  " -NoNewline
    Write-Host -ForegroundColor DarkGray "Page $($Page + 1)/$totalPages" -NoNewline
    Write-Host "                       " -NoNewline
    Write-Host -ForegroundColor Cyan "|"

    # Footer
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"
    $time = Get-Date -Format "HH:mm:ss"
    Write-Host -ForegroundColor Cyan "|  " -NoNewline
    Write-Host -ForegroundColor DarkGray "$time" -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host -ForegroundColor DarkGray "Refresh: ${script:REFRESH_RATE}s" -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host -ForegroundColor DarkGray "Launch: " -NoNewline
    Write-Host -ForegroundColor White "/bga <task>" -NoNewline
    Write-Host "  |  " -NoNewline
    Write-Host -ForegroundColor DarkGray "Kill: " -NoNewline
    Write-Host -ForegroundColor White "agents kill <id>" -NoNewline
    Write-Host "               " -NoNewline
    Write-Host -ForegroundColor Cyan "|"
    Write-Host -ForegroundColor Cyan "+============================================================================================================+"

    return $totalPages
}

function Watch-Agents {
    param([switch]$NotifyMode)

    $notify = $NotifyMode.IsPresent
    if ($notify) { Save-State }
    $waitingForDetail = $false

    while ($true) {
        if ($notify) { Check-Completions -NotifyMode }
        $totalPages = Show-Status -NotifyMode:$notify -FilterMode $script:FilterMode -Page $script:CurrentPage

        # Check for keypress during refresh interval
        $elapsed = 0
        while ($elapsed -lt ($script:REFRESH_RATE * 1000)) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # Detail mode (D was pressed, waiting for number)
                if ($waitingForDetail) {
                    $waitingForDetail = $false
                    if ($key.KeyChar -ge '1' -and $key.KeyChar -le '9') {
                        $index = [int]$key.KeyChar - [int]'1'
                        Show-AgentDetails -Index $index
                    }
                    break
                }

                # Normal key handling
                switch ($key.Key) {
                    'N' {
                        $notify = -not $notify
                        if ($notify) { Save-State }
                        break
                    }
                    'Q' { return }
                    'Escape' { return }
                    'R' {
                        $script:FilterMode = "RUNNING"
                        $script:CurrentPage = 0
                        break
                    }
                    'F' {
                        $script:FilterMode = "FINISHED"
                        $script:CurrentPage = 0
                        break
                    }
                    'A' {
                        $script:FilterMode = "ALL"
                        $script:CurrentPage = 0
                        break
                    }
                    'C' {
                        # Copy first running agent ID
                        if ($script:CachedFiles.Count -gt 0) {
                            $runningFile = $script:CachedFiles | Where-Object { Test-AgentRunning -FilePath $_.FullName } | Select-Object -First 1
                            if ($runningFile) {
                                Set-Clipboard -Value $runningFile.BaseName
                                Set-StatusMessage "Copied: $($runningFile.BaseName)"
                            } else {
                                Set-Clipboard -Value $script:CachedFiles[0].BaseName
                                Set-StatusMessage "Copied: $($script:CachedFiles[0].BaseName)"
                            }
                        }
                        break
                    }
                    'D' {
                        $waitingForDetail = $true
                        continue
                    }
                    'PageUp' {
                        if ($script:CurrentPage -gt 0) { $script:CurrentPage-- }
                        break
                    }
                    'PageDown' {
                        if ($script:CurrentPage -lt $totalPages - 1) { $script:CurrentPage++ }
                        break
                    }
                    'Add' {  # + key
                        if ($script:REFRESH_RATE -lt 10) {
                            $rates = @(1, 2, 3, 5, 10)
                            $currentIndex = [array]::IndexOf($rates, $script:REFRESH_RATE)
                            if ($currentIndex -lt $rates.Count - 1) {
                                $script:REFRESH_RATE = $rates[$currentIndex + 1]
                            }
                        }
                        break
                    }
                    'Subtract' {  # - key
                        if ($script:REFRESH_RATE -gt 1) {
                            $rates = @(1, 2, 3, 5, 10)
                            $currentIndex = [array]::IndexOf($rates, $script:REFRESH_RATE)
                            if ($currentIndex -gt 0) {
                                $script:REFRESH_RATE = $rates[$currentIndex - 1]
                            }
                        }
                        break
                    }
                    'OemPlus' {  # + on main keyboard
                        if ($script:REFRESH_RATE -lt 10) {
                            $rates = @(1, 2, 3, 5, 10)
                            $currentIndex = [array]::IndexOf($rates, $script:REFRESH_RATE)
                            if ($currentIndex -lt $rates.Count - 1) {
                                $script:REFRESH_RATE = $rates[$currentIndex + 1]
                            }
                        }
                        break
                    }
                    'OemMinus' {  # - on main keyboard
                        if ($script:REFRESH_RATE -gt 1) {
                            $rates = @(1, 2, 3, 5, 10)
                            $currentIndex = [array]::IndexOf($rates, $script:REFRESH_RATE)
                            if ($currentIndex -gt 0) {
                                $script:REFRESH_RATE = $rates[$currentIndex - 1]
                            }
                        }
                        break
                    }
                    default {
                        # Number keys 1-9 for quick view
                        if ($key.KeyChar -ge '1' -and $key.KeyChar -le '9') {
                            $index = [int]$key.KeyChar - [int]'1'
                            Show-QuickView -Index $index
                        }
                    }
                }
                break
            }
            Start-Sleep -Milliseconds 100
            $elapsed += 100
        }
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
        } else {
            "STATUS: KILLED" | Set-Content -Path $metaFile
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
        $isRunning = Test-AgentRunning -FilePath $file.FullName
        $taskTitle = Get-TaskTitle -AgentId $agentId -OutputFile $file.FullName
        $elapsed = Get-ElapsedTime -AgentId $agentId -OutputFile $file.FullName -IsRunning:$isRunning

        if ($isRunning) {
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
            $status = Get-AgentStatus -OutputFile $file.FullName -AgentId $agentId
            $icon = switch ($status) {
                "SUCCESS" { Write-Host -ForegroundColor Green "  $([char]0x2713)" -NoNewline; "" }
                "FAILED" { Write-Host -ForegroundColor Red "  $([char]0x2717)" -NoNewline; "" }
                "KILLED" { Write-Host -ForegroundColor Yellow "  $([char]0x26A0)" -NoNewline; "" }
            }
            if ($taskTitle) {
                Write-Host " $taskTitle" -NoNewline
                Write-Host -ForegroundColor DarkGray " ($agentId)"
            } else {
                Write-Host " $agentId"
            }
        }
    }

    if ($found -eq 0) {
        Write-Host "  No recent agents"
    } else {
        Write-Host ""
        Write-Host -ForegroundColor Green "  $([char]0x25CF)" -NoNewline
        Write-Host " = running  " -NoNewline
        Write-Host -ForegroundColor Green "$([char]0x2713)" -NoNewline
        Write-Host " = success  " -NoNewline
        Write-Host -ForegroundColor Red "$([char]0x2717)" -NoNewline
        Write-Host " = failed  " -NoNewline
        Write-Host -ForegroundColor Yellow "$([char]0x26A0)" -NoNewline
        Write-Host " = killed"
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
        $taskTitle = Get-TaskTitle -AgentId $AgentId -OutputFile $outputFile.FullName
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
    Write-Host -ForegroundColor White "Agent Monitor v2.0" -NoNewline
    Write-Host " - Dashboard for Claude Code background agents"
    Write-Host ""
    Write-Host "Usage: agents [command]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host -ForegroundColor White "  (none)         " -NoNewline
    Write-Host "Start watching dashboard (default)"
    Write-Host -ForegroundColor White "  n              " -NoNewline
    Write-Host "Watch + notifications enabled"
    Write-Host -ForegroundColor White "  status         " -NoNewline
    Write-Host "Show current status once"
    Write-Host -ForegroundColor White "  list           " -NoNewline
    Write-Host "List all recent agents"
    Write-Host -ForegroundColor White "  tail <id>      " -NoNewline
    Write-Host "Follow agent output"
    Write-Host -ForegroundColor White "  kill <id>      " -NoNewline
    Write-Host "Kill a running agent"
    Write-Host -ForegroundColor White "  help           " -NoNewline
    Write-Host "Show this help"
    Write-Host ""
    Write-Host "Keyboard shortcuts (in watch mode):"
    Write-Host -ForegroundColor White "  N              " -NoNewline
    Write-Host "Toggle notifications on/off"
    Write-Host -ForegroundColor White "  R / F / A      " -NoNewline
    Write-Host "Filter: Running / Finished / All"
    Write-Host -ForegroundColor White "  + / -          " -NoNewline
    Write-Host "Adjust refresh rate (1-10s)"
    Write-Host -ForegroundColor White "  C              " -NoNewline
    Write-Host "Copy agent ID to clipboard"
    Write-Host -ForegroundColor White "  1-9            " -NoNewline
    Write-Host "Quick view agent output"
    Write-Host -ForegroundColor White "  D + 1-9        " -NoNewline
    Write-Host "Show agent details"
    Write-Host -ForegroundColor White "  PgUp / PgDn    " -NoNewline
    Write-Host "Navigate pages"
    Write-Host -ForegroundColor White "  Q / Esc        " -NoNewline
    Write-Host "Quit"
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
