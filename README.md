# 🤖 Claude Agents TUI

**A beautiful terminal dashboard for monitoring Claude Code background agents in real-time.**

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)

> Transform your Claude Code workflow with live monitoring, progress tracking, and instant notifications when background agents complete their tasks.

---

## ✨ Features

- 📊 **Real-time Dashboard** - Beautiful table view with live updates every 2 seconds
- 🎯 **Task Titles** - See what each agent is actually doing, not just cryptic IDs
- 📍 **Project Context** - Know which codebase each agent is working in
- ⏱️ **Time Tracking** - Monitor how long agents have been running
- 📈 **Progress Bars** - Visual progress based on tool usage
- 🔔 **macOS Notifications** - Get notified when agents complete (with sound!)
- 🎨 **Color-coded Status** - Green for running, yellow for done
- 🔪 **Kill Command** - Stop runaway agents instantly
- 📝 **Live Action Updates** - See which tool each agent is currently using

---

## 📸 Preview

```
╔═════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                🤖 CLAUDE CODE BACKGROUND AGENTS                          🔔 NOTIFY ON             ║
╠═════════════════════════════════════════════════════════════════════════════════════════════════════╣
║ TASK                         │ PROJECT    │ STATUS   │ TIME    │ PROGRESS     │ ACTION         ║
╠══════════════════════════════╪════════════╪══════════╪═════════╪══════════════╪════════════════╣
║ Research AI avatar pricing   │ Assistant  │ ⠋ RUN    │ 2m 15s  │ ████░░░░░░   │ WebSearch      ║
║                              │            │          │         │              │                ║
║ Scrape API docs              │ v-life     │ ⠙ RUN    │ 1m 03s  │ ██░░░░░░░░   │ Read           ║
║                              │            │          │         │              │                ║
║ Generate startup ideas       │ Assistant  │ ✓ DONE   │ 3m 45s  │ ██████████   │ -              ║
║                              │            │          │         │              │                ║
╠═════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  SUMMARY: ● 2 running   ○ 1 completed   Total: 3                                                 ║
╠═════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  17:09:16   │   Refresh: 2s   │   Kill: agents kill <id>   │   Ctrl+C exit                       ║
╚═════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 🚀 Quick Start

### Prerequisites

- **macOS** (tested on macOS 15+)
- **Claude Code** CLI installed
- **zsh** or **bash** shell

### Installation

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

### Manual Installation

If you prefer to install manually:

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

## 📖 Usage

### Basic Commands

```bash
# Start the live dashboard with notifications (recommended)
agents n

# Show current status (one-time)
agents status

# List all recent agents
agents list

# Follow a specific agent's output
agents tail <agent_id>

# Kill a running agent
agents kill <agent_id>

# Launch tmux split-screen dashboard
agents tmux

# Test notifications
agents test

# Clean up old agent files (>2 hours)
agents cleanup
```

### Launching Background Agents

Use the `/bga` skill from within Claude Code conversations:

```
You: /bga research the top 5 AI coding assistants and compare pricing

Claude: 🚀 Agent launched: Research AI assistants
```

The agent will:
- Run in the background
- Show up in the dashboard with a clear title
- Send you a notification when done
- Track progress and tool usage

---

## 🎯 Use Cases

### Development Workflow

```bash
# Terminal 1: Your main Claude Code session
claude

# Terminal 2: Agent monitor dashboard
agents n
```

Launch multiple agents in parallel and monitor them all:
- Research tasks while you code
- Background file analysis while you implement
- Documentation generation while you test

### Example Workflow

```
You: /bga scrape the pricing page at example.com and summarize it
Claude: 🚀 Agent launched: Scrape pricing page

You: /bga refactor the utils folder to use TypeScript
Claude: 🚀 Agent launched: Refactor to TypeScript

You: /bga run comprehensive tests on the API endpoints
Claude: 🚀 Agent launched: Run API tests
```

All three agents run in parallel, visible in the dashboard with:
- Clear titles
- Progress tracking
- Project context
- Time elapsed
- Current tool being used

---

## ⚙️ How It Works

### Agent Detection

The monitor scans `/private/tmp/claude/` for agent output files and displays:
- **Title**: From metadata file `/tmp/agent-meta-<id>.txt`
- **Project**: Extracted from output file path
- **Status**: Based on file modification time (active = modified in last 60s)
- **Progress**: Calculated from tool usage count
- **Action**: Last tool used by the agent

### Notifications

When an agent transitions from "running" to "done":
1. State is tracked in `/tmp/agent-monitor-state`
2. Completion is detected on next refresh
3. macOS notification sent via `terminal-notifier` (or `osascript` fallback)
4. Notification includes task title (if available) or agent ID

### Metadata Files

The `/bga` skill automatically creates metadata files:

```bash
/tmp/agent-meta-<agent_id>.txt:
  TITLE: <task title>
  STARTED: <HH:MM:SS>
  TASK: <full task description>
```

---

## 🎨 Customization

### Change Refresh Rate

Edit `agent-monitor.sh`:

```bash
REFRESH_RATE=2  # Change to desired seconds
```

### Modify Progress Bar

Progress is estimated based on tool count. Adjust in `progress_bar()`:

```bash
local max=20  # Assume ~20 tools for 100% progress
```

### Customize Notification Sound

Edit the `send_notification()` function:

```bash
terminal-notifier -title "$title" -message "$message" -sound Glass  # Change Glass to another sound
```

Available sounds: `Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`, `Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`

---

## 🔧 Troubleshooting

### "command not found: agents"

**Solution:** Restart your terminal or run:
```bash
source ~/.zshrc  # or ~/.bashrc
```

### Notifications not working

**Check permissions:**
1. Go to **System Settings → Notifications**
2. Find **terminal-notifier** or **Script Editor**
3. Enable **Allow Notifications**

**Test notifications:**
```bash
agents test
```

### Progress bar not updating

Progress is based on tool usage. Very simple tasks (like "count to 10") may use few tools and show minimal progress. This is expected behavior.

### Agent not showing in dashboard

**Possible causes:**
1. Agent completed >30 minutes ago (only recent agents shown)
2. No metadata file created (use `/bga` skill to launch)
3. Agent running in different project (check with `agents list`)

---

## 🤝 Contributing

Contributions are welcome! Here's how:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit your changes**: `git commit -m 'Add amazing feature'`
4. **Push to branch**: `git push origin feature/amazing-feature`
5. **Open a Pull Request**

### Ideas for Contributions

- [ ] Linux support
- [ ] Windows (WSL) support
- [ ] Custom themes/color schemes
- [ ] Export agent logs to file
- [ ] Web-based dashboard
- [ ] Agent priority levels
- [ ] Estimated completion time
- [ ] Agent dependencies (run B after A completes)
- [ ] Slack/Discord notifications
- [ ] Agent retry on failure

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built for the [Claude Code](https://claude.com/claude-code) community
- Inspired by htop, k9s, and other great TUI tools
- Thanks to everyone who provided feedback during development

---

## 📬 Support

- **Issues**: [GitHub Issues](https://github.com/mrchevyceleb/claude-agents-tui/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mrchevyceleb/claude-agents-tui/discussions)
- **Twitter**: [@mrchevyceleb](https://twitter.com/mrchevyceleb)

---

**Made with ❤️ for the Claude Code community**

*Star ⭐ this repo if you find it useful!*
