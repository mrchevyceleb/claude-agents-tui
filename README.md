# Claude Agents TUI

**A beautiful terminal dashboard for monitoring Claude Code background agents in real-time.**

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey.svg)
![Version](https://img.shields.io/badge/version-2.0-green.svg)

> Transform your Claude Code workflow with live monitoring, progress tracking, and instant notifications when background agents complete their tasks.

---

## Features

### Core Features
- **Real-time Dashboard** - Beautiful table view with configurable refresh rate (1-10s)
- **Task Titles** - See what each agent is actually doing, not just cryptic IDs
- **Project Context** - Know which codebase each agent is working in
- **Time Tracking** - Monitor how long agents have been running
- **Progress Bars** - Visual progress based on tool usage
- **Color-coded Status** - Green for running, yellow for done, red for failed

### v2.0 New Features
- **Error Detection** - Automatic success/failed/killed status detection
- **Sound Notifications** - Audio alert when agents complete (different sound for failures)
- **Quick View (1-9)** - Press a number to preview agent output inline
- **Agent Details (D+1-9)** - Full agent details panel with all metadata
- **Copy Agent ID (C)** - One-key copy to clipboard for kill commands
- **Filter View (R/F/A)** - Toggle between Running/Finished/All agents
- **Pagination (PgUp/PgDn)** - Browse through all agents, 10 per page
- **Adjustable Refresh (+/-)** - Change refresh rate on the fly (1s to 10s)
- **Success Rate** - Summary shows success/fail counts
- **Completion Time** - Shows actual duration for completed agents

---

## Preview

```
+============================================================================================================+
|                              CLAUDE CODE BACKGROUND AGENTS                               |
+------------------------------------------------------------------------------------------------------------+
|  [N] Notify: ON   [R/F/A] Filter: ALL   [+/-] Speed: 2s   [C] Copy   [Q] Quit               |
|  [1-9] Quick view   [D]+[1-9] Details   [PgUp/PgDn] Page                                     |
+============================================================================================================+
| # | TASK                       | PROJECT    | STATUS     | TIME      | PROGRESS     | ACTION       |
+===+============================+============+============+===========+==============+==============+
| 1 | Research AI pricing        | Assistant  | * RUNNING  | 2m 15s    | ####......   | WebSearch    |
| 2 | Scrape API docs            | v-life     | * RUNNING  | 1m 03s    | ##........   | Read         |
| 3 | Generate startup ideas     | Assistant  | V SUCCESS  | 3m 45s    | ##########   | -            |
| 4 | Fix auth bug               | r-link     | X FAILED   | 5m 12s    | ########..   | -            |
+============================================================================================================+
|  SUMMARY: * 2 running   o 2 done (1V 1X)   Total: 4   Page 1/1                               |
+============================================================================================================+
|  17:09:16  |  Refresh: 2s  |  Launch: /bga <task>  |  Kill: agents kill <id>               |
+============================================================================================================+
```

---

## Quick Start

### Prerequisites

**macOS:**
- macOS 15+
- Claude Code CLI installed
- zsh or bash shell

**Windows:**
- Windows 10/11
- Claude Code CLI installed
- PowerShell 5.1+

---

### macOS Installation

```bash
# Clone the repository
git clone https://github.com/mrchevyceleb/claude-agents-tui.git
cd claude-agents-tui

# Run the installer
./install.sh
```

The installer will:
1. Copy `agent-monitor.sh` to `~/.claude/scripts/`
2. Copy `bga.md` to `~/.claude/commands/`
3. Add the `agents` alias to your shell config
4. Install `terminal-notifier` for better notifications

#### Manual Installation (macOS)

```bash
# Create directories
mkdir -p ~/.claude/scripts ~/.claude/commands

# Copy files
cp agent-monitor.sh ~/.claude/scripts/
cp bga.md ~/.claude/commands/

# Make executable
chmod +x ~/.claude/scripts/agent-monitor.sh

# Add alias to your shell config (~/.zshrc or ~/.bashrc)
echo 'alias agents="$HOME/.claude/scripts/agent-monitor.sh"' >> ~/.zshrc

# Reload shell
source ~/.zshrc

# Install terminal-notifier (optional, for better notifications)
brew install terminal-notifier
```

---

### Windows Installation

```powershell
# Clone the repository
git clone https://github.com/mrchevyceleb/claude-agents-tui.git
cd claude-agents-tui

# Create directories
mkdir -Force "$env:USERPROFILE\.claude\scripts"
mkdir -Force "$env:USERPROFILE\.claude\commands"

# Copy files
Copy-Item agent-monitor.ps1 "$env:USERPROFILE\.claude\scripts\"
Copy-Item agents.cmd "$env:USERPROFILE\.claude\scripts\"
Copy-Item bga.md "$env:USERPROFILE\.claude\commands\"

# Add to PATH (run once)
$scriptsPath = "$env:USERPROFILE\.claude\scripts"
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($currentPath -notlike "*$scriptsPath*") {
    [Environment]::SetEnvironmentVariable('Path', "$currentPath;$scriptsPath", 'User')
}

# Restart terminal for PATH changes to take effect
```

#### Optional: Better Windows Notifications

```powershell
# Install BurntToast for richer notifications
Install-Module -Name BurntToast -Scope CurrentUser
```

---

## Usage

### Basic Commands

```bash
# Start the live dashboard (default)
agents

# Start with notifications enabled
agents n

# Show current status (one-time)
agents status

# List all recent agents
agents list

# Follow a specific agent's output
agents tail <agent_id>

# Kill a running agent
agents kill <agent_id>

# Show help
agents help
```

### Keyboard Shortcuts (Watch Mode)

| Key | Action |
|-----|--------|
| `N` | Toggle notifications on/off |
| `R` | Filter: Running agents only |
| `F` | Filter: Finished agents only |
| `A` | Filter: All agents |
| `+` / `-` | Increase/decrease refresh rate (1-10s) |
| `C` | Copy agent ID to clipboard |
| `1-9` | Quick view: Preview agent output |
| `D` + `1-9` | Show full agent details |
| `PgUp` / `PgDn` | Navigate pages |
| `Q` / `Esc` | Quit dashboard |

### Launching Background Agents

Use the `/bga` skill from within Claude Code conversations:

```
You: /bga research the top 5 AI coding assistants and compare pricing

Claude: Agent launched: Research AI assistants
```

The agent will:
- Run in the background
- Show up in the dashboard with a clear title
- Send you a notification when done
- Track progress and tool usage

---

## Use Cases

### Development Workflow

```bash
# Terminal 1: Your main Claude Code session
claude

# Terminal 2: Agent monitor dashboard
agents
```

Launch multiple agents in parallel and monitor them all:
- Research tasks while you code
- Background file analysis while you implement
- Documentation generation while you test

### Example Workflow

```
You: /bga scrape the pricing page at example.com and summarize it
Claude: Agent launched: Scrape pricing page

You: /bga refactor the utils folder to use TypeScript
Claude: Agent launched: Refactor to TypeScript

You: /bga run comprehensive tests on the API endpoints
Claude: Agent launched: Run API tests
```

All three agents run in parallel, visible in the dashboard with:
- Clear titles
- Progress tracking
- Project context
- Time elapsed
- Current tool being used
- Success/failure status when complete

---

## How It Works

### Agent Detection

The monitor scans temp directories for agent output files and displays:
- **Title**: From metadata file or extracted from project path
- **Project**: Extracted from output file path
- **Status**: Running/Success/Failed/Killed based on file activity and error detection
- **Progress**: Calculated from tool usage count
- **Action**: Last tool used by the agent

### Status Detection

| Status | Color | Meaning |
|--------|-------|---------|
| RUNNING | Green | Agent actively working (file modified <60s ago) |
| SUCCESS | Green | Agent completed without errors |
| FAILED | Red | Agent encountered errors |
| KILLED | Yellow | Agent was manually terminated |

### Notifications

When an agent transitions from "running" to "done":
1. State is tracked in temp files
2. Completion is detected on next refresh
3. Sound plays (different for success vs failure)
4. Visual notification sent
5. Status (success/failed) determined from output analysis

### Metadata Files

The `/bga` skill automatically creates metadata files:

```bash
/tmp/agent-meta-<agent_id>.txt:
  TITLE: <task title>
  STARTED: <HH:MM:SS>
  TASK: <full task description>
```

---

## Customization

### Change Default Refresh Rate

Edit the script and change:

```powershell
$script:REFRESH_RATE = 2  # Change to desired seconds (1-10)
```

Or use `+`/`-` keys during runtime.

### Modify Progress Bar

Progress is estimated based on tool count. Adjust in the script:

```powershell
$max = 20  # Assume ~20 tools for 100% progress
```

### Customize Notification Sound (macOS)

Edit the `send_notification()` function:

```bash
terminal-notifier -title "$title" -message "$message" -sound Glass  # Change Glass to another sound
```

Available sounds: `Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`, `Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`

---

## Troubleshooting

### "command not found: agents"

**Solution:** Restart your terminal or run:
```bash
source ~/.zshrc  # or ~/.bashrc
```

### Notifications not working

**Check permissions:**
1. Go to **System Settings > Notifications**
2. Find **terminal-notifier** or **Script Editor**
3. Enable **Allow Notifications**

**Test notifications:**
```bash
agents test
```

### Progress bar not updating

Progress is based on tool usage. Very simple tasks may use few tools and show minimal progress. This is expected behavior.

### Agent not showing in dashboard

**Possible causes:**
1. Agent completed >30 minutes ago (only recent agents shown)
2. No metadata file created (use `/bga` skill to launch)
3. Agent running in different project (check with `agents list`)

### Task titles showing as IDs

If you see IDs like "b39987a..." instead of task titles:
1. Make sure to launch agents using `/bga` command (creates metadata)
2. The dashboard will fall back to project name + "task" if no metadata

---

## Contributing

Contributions are welcome! Here's how:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit your changes**: `git commit -m 'Add amazing feature'`
4. **Push to branch**: `git push origin feature/amazing-feature`
5. **Open a Pull Request**

### Ideas for Contributions

- [ ] Linux support
- [x] Windows support (native PowerShell)
- [x] Error detection (success/failed status)
- [x] Sound notifications
- [x] Quick view agent output
- [x] Agent details panel
- [x] Copy agent ID to clipboard
- [x] Filter views (running/finished/all)
- [x] Pagination for large agent lists
- [x] Adjustable refresh rate
- [x] Success rate tracking
- [ ] Custom themes/color schemes
- [ ] Export agent logs to file
- [ ] Web-based dashboard
- [ ] Agent priority levels
- [ ] Agent dependencies (run B after A completes)
- [ ] Slack/Discord notifications
- [ ] Agent retry on failure

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Built for the [Claude Code](https://claude.com/claude-code) community
- Inspired by htop, k9s, and other great TUI tools
- Thanks to everyone who provided feedback during development

---

## Support

- **Issues**: [GitHub Issues](https://github.com/mrchevyceleb/claude-agents-tui/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mrchevyceleb/claude-agents-tui/discussions)

---

**Made with love for the Claude Code community**

*Star this repo if you find it useful!*
