#!/bin/bash
# Claude Agents TUI - Installation Script
# https://github.com/yourusername/claude-agents-tui

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════════════╗"
echo "║   🤖 Claude Agents TUI - Installation         ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${YELLOW}Warning: This tool is designed for macOS. Some features may not work on other platforms.${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create directories
echo -e "${GREEN}→${NC} Creating directories..."
mkdir -p ~/.claude/scripts
mkdir -p ~/.claude/commands

# Copy files
echo -e "${GREEN}→${NC} Installing agent-monitor.sh..."
cp agent-monitor.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/agent-monitor.sh

echo -e "${GREEN}→${NC} Installing bga.md skill..."
cp bga.md ~/.claude/commands/

# Detect shell
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
else
    SHELL_CONFIG="$HOME/.zshrc"  # Default to zsh
fi

# Add alias if not already present
if ! grep -q "agent-monitor" "$SHELL_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}→${NC} Adding 'agents' alias to $SHELL_CONFIG..."
    echo "" >> "$SHELL_CONFIG"
    echo "# Claude Code Agent Monitor" >> "$SHELL_CONFIG"
    echo "alias agents='$HOME/.claude/scripts/agent-monitor.sh'" >> "$SHELL_CONFIG"
else
    echo -e "${YELLOW}→${NC} Alias already exists in $SHELL_CONFIG"
fi

# Install terminal-notifier if not present
if ! command -v terminal-notifier &> /dev/null; then
    echo -e "${GREEN}→${NC} Installing terminal-notifier for better notifications..."
    if command -v brew &> /dev/null; then
        brew install terminal-notifier
    else
        echo -e "${YELLOW}⚠${NC}  Homebrew not found. Skipping terminal-notifier installation."
        echo -e "   Install manually with: ${BOLD}brew install terminal-notifier${NC}"
    fi
else
    echo -e "${GREEN}✓${NC} terminal-notifier already installed"
fi

echo ""
echo -e "${BOLD}${GREEN}✨ Installation complete!${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Restart your terminal or run: ${BOLD}source $SHELL_CONFIG${NC}"
echo -e "  2. Launch the monitor: ${BOLD}agents n${NC}"
echo -e "  3. In Claude Code, use: ${BOLD}/bga <task>${NC} to launch background agents"
echo ""
echo -e "Commands:"
echo -e "  ${BOLD}agents n${NC}          - Live dashboard with notifications"
echo -e "  ${BOLD}agents list${NC}       - Quick status check"
echo -e "  ${BOLD}agents kill <id>${NC}  - Stop a running agent"
echo -e "  ${BOLD}agents test${NC}       - Test notifications"
echo ""
echo -e "Documentation: ${CYAN}https://github.com/yourusername/claude-agents-tui${NC}"
echo ""
