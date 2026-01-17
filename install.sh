#!/bin/bash
# Claude Agents TUI - macOS One-Click Installer
# Downloads and installs everything from GitHub

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/mrchevyceleb/claude-agents-tui/main"

echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║   🤖 Claude Agents TUI - macOS Installation   ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${YELLOW}Warning: This installer is designed for macOS.${NC}"
    echo -e "${YELLOW}For Linux, you may need to modify the scripts.${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create directories
echo -e "${GREEN}[1/5]${NC} Creating directories..."
mkdir -p ~/.claude/scripts
mkdir -p ~/.claude/commands
echo -e "      Created: ~/.claude/scripts"
echo -e "      Created: ~/.claude/commands"

# Download files
echo ""
echo -e "${GREEN}[2/5]${NC} Downloading files from GitHub..."

# Download agent-monitor.sh
echo -e "      Downloading agent-monitor.sh..."
if curl -fsSL "$REPO_URL/agent-monitor.sh" -o ~/.claude/scripts/agent-monitor.sh; then
    chmod +x ~/.claude/scripts/agent-monitor.sh
    echo -e "${GREEN}      ✓${NC} Downloaded: agent-monitor.sh"
else
    echo -e "${RED}      ✗ Failed to download agent-monitor.sh${NC}"
    exit 1
fi

# Download bga.md
echo -e "      Downloading bga.md..."
if curl -fsSL "$REPO_URL/bga.md" -o ~/.claude/commands/bga.md; then
    echo -e "${GREEN}      ✓${NC} Downloaded: bga.md (skill)"
else
    echo -e "${RED}      ✗ Failed to download bga.md${NC}"
    exit 1
fi

# Detect shell
echo ""
echo -e "${GREEN}[3/5]${NC} Configuring shell..."
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
else
    # Default to zsh (macOS default since Catalina)
    SHELL_CONFIG="$HOME/.zshrc"
fi

# Add alias if not already present
if ! grep -q "agent-monitor" "$SHELL_CONFIG" 2>/dev/null; then
    echo -e "      Adding 'agents' alias to $SHELL_CONFIG..."
    echo "" >> "$SHELL_CONFIG"
    echo "# Claude Code Agent Monitor" >> "$SHELL_CONFIG"
    echo "alias agents='\$HOME/.claude/scripts/agent-monitor.sh'" >> "$SHELL_CONFIG"
    echo -e "${GREEN}      ✓${NC} Added alias to $SHELL_CONFIG"
else
    echo -e "${YELLOW}      ⚠${NC} Alias already exists in $SHELL_CONFIG"
fi

# Install terminal-notifier if not present
echo ""
echo -e "${GREEN}[4/5]${NC} Checking for terminal-notifier (optional)..."
if ! command -v terminal-notifier &> /dev/null; then
    if command -v brew &> /dev/null; then
        echo -e "      Installing terminal-notifier via Homebrew..."
        brew install terminal-notifier
        echo -e "${GREEN}      ✓${NC} Installed terminal-notifier"
    else
        echo -e "${YELLOW}      ⚠${NC}  Homebrew not found. Skipping terminal-notifier."
        echo -e "         Install manually with: ${BOLD}brew install terminal-notifier${NC}"
    fi
else
    echo -e "${GREEN}      ✓${NC} terminal-notifier already installed"
fi

echo ""
echo -e "${GREEN}[5/5]${NC} Installation complete!"
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              Next Steps:                       ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  1. Restart your terminal or run:"
echo -e "     ${BOLD}source $SHELL_CONFIG${NC}"
echo ""
echo -e "  2. Start the dashboard:"
echo -e "     ${BOLD}agents${NC}"
echo ""
echo -e "  3. Launch agents with:"
echo -e "     ${BOLD}/bga <task>${NC}"
echo ""
echo -e "${BOLD}Examples:${NC}"
echo -e "  ${CYAN}/bga research the top 5 AI coding tools${NC}"
echo -e "  ${CYAN}/bga refactor the auth system${NC}"
echo -e "  ${CYAN}/bga run comprehensive tests${NC}"
echo ""
echo -e "${BOLD}Dashboard shortcuts:${NC}"
echo -e "  N     - Toggle notifications"
echo -e "  1-9   - Quick view agent output"
echo -e "  D+1-9 - Show agent details"
echo -e "  R/F/A - Filter running/finished/all"
echo -e "  Q     - Quit"
echo ""
echo -e "For more info: ${CYAN}https://github.com/mrchevyceleb/claude-agents-tui${NC}"
echo ""
