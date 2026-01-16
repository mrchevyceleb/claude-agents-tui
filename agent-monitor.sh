#!/bin/bash
# Agent Monitor - Visual dashboard for Claude Code background agents
# Usage: agent-monitor.sh [watch|tmux|status|notify|kill]

AGENT_DIR="/private/tmp/claude"
META_DIR="/tmp"
REFRESH_RATE=2
STATE_FILE="/tmp/agent-monitor-state"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# macOS notification
send_notification() {
    local title="$1"
    local message="$2"
    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "$title" -message "$message" -sound Glass -ignoreDnD
    elif [ -f /opt/homebrew/bin/terminal-notifier ]; then
        /opt/homebrew/bin/terminal-notifier -title "$title" -message "$message" -sound Glass -ignoreDnD
    else
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\""
    fi
}

is_running() {
    local file="$1"
    [ "$(find "$file" -mmin -1 2>/dev/null)" ]
}

get_task_title() {
    local agent_id="$1"
    local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
    if [ -f "$meta_file" ]; then
        grep "^TITLE:" "$meta_file" 2>/dev/null | sed 's/^TITLE: //'
    fi
}

get_start_time() {
    local agent_id="$1"
    local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
    if [ -f "$meta_file" ]; then
        grep "^STARTED:" "$meta_file" 2>/dev/null | sed 's/^STARTED: //'
    fi
}

# Calculate elapsed time from start
get_elapsed() {
    local agent_id="$1"
    local output_file="$2"

    # Try to get start time from meta file
    local start_time=$(get_start_time "$agent_id")

    if [ -n "$start_time" ]; then
        # Parse start time and calculate diff
        local start_epoch=$(date -j -f "%H:%M:%S" "$start_time" "+%s" 2>/dev/null)
        local now_epoch=$(date "+%s")
        if [ -n "$start_epoch" ]; then
            local diff=$((now_epoch - start_epoch))
            # Handle day rollover
            [ $diff -lt 0 ] && diff=$((diff + 86400))
            local mins=$((diff / 60))
            local secs=$((diff % 60))
            printf "%dm %02ds" $mins $secs
            return
        fi
    fi

    # Fallback: use file modification time
    local mod_time=$(stat -f "%m" "$output_file" 2>/dev/null)
    local now=$(date "+%s")
    if [ -n "$mod_time" ]; then
        local diff=$((now - mod_time))
        if [ $diff -lt 60 ]; then
            echo "<1m"
        else
            echo "$((diff / 60))m"
        fi
    else
        echo "-"
    fi
}

# Progress bar based on tool count
progress_bar() {
    local tools="$1"
    local width=10

    # Estimate progress (assume ~20 tools for a typical task)
    local max=20
    local filled=$((tools * width / max))
    [ $filled -gt $width ] && filled=$width

    local empty=$((width - filled))

    printf "${GREEN}"
    for ((i=0; i<filled; i++)); do printf "█"; done
    printf "${DIM}"
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "${NC}"
}

get_progress_info() {
    local output_file="$1"
    local tool_count=$(grep -c '"tool_use"' "$output_file" 2>/dev/null || echo "0")
    local last_tool=$(grep '"tool_use"' "$output_file" 2>/dev/null | tail -1 | sed 's/.*"name":"\([^"]*\)".*/\1/' 2>/dev/null | head -c 15)
    local last_text=$(grep '"text"' "$output_file" 2>/dev/null | tail -1 | sed 's/.*"text":"\([^"]*\)".*/\1/' 2>/dev/null | tr '\\n' ' ' | head -c 40)
    echo "${tool_count}|${last_tool}|${last_text}"
}

# Extract project name from output file path
get_project_name() {
    local output_file="$1"
    # Path looks like: /private/tmp/claude/-Users-mjohnst-Documents-ELITE-PROJECTS-v-life/tasks/xxx.output
    # Extract the folder name and get the last meaningful part
    local dir_path=$(dirname "$(dirname "$output_file")")
    local folder_name=$(basename "$dir_path")

    # Clean up the folder name (remove leading dash and convert dashes to readable format)
    # e.g., "-Users-mjohnst-Documents-ELITE-PROJECTS-v-life" -> "v-life"
    # e.g., "-Users-mjohnst-Library-CloudStorage-OneDrive-Personal-Documents-ASSISTANT-HUB-Assistant" -> "Assistant"

    # Get the last segment after the last hyphen-word pattern
    local project=$(echo "$folder_name" | sed 's/.*-//' | head -c 12)

    # If it's too generic, try to get a better name
    if [ "$project" = "tasks" ] || [ -z "$project" ]; then
        project=$(echo "$folder_name" | rev | cut -d'-' -f1 | rev | head -c 12)
    fi

    echo "$project"
}

get_running_agents() {
    local running=""
    while IFS= read -r output_file; do
        [ -z "$output_file" ] && continue
        if is_running "$output_file"; then
            agent_id=$(basename "$output_file" .output)
            running="$running $agent_id"
        fi
    done < <(find "$AGENT_DIR" -name "*.output" 2>/dev/null)
    echo "$running"
}

save_state() {
    get_running_agents > "$STATE_FILE"
}

check_completions() {
    if [ ! -f "$STATE_FILE" ]; then
        save_state
        return
    fi
    local previous=$(cat "$STATE_FILE")
    local current=$(get_running_agents)
    for agent_id in $previous; do
        if ! echo "$current" | grep -q "$agent_id"; then
            local title=$(get_task_title "$agent_id")
            if [ -n "$title" ]; then
                send_notification "✅ Complete" "$title"
            else
                send_notification "✅ Complete" "Agent $agent_id"
            fi
        fi
    done
    echo "$current" > "$STATE_FILE"
}

show_status() {
    local notify_mode="${1:-false}"
    clear

    # Header
    echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    if [ "$notify_mode" = "true" ]; then
        echo -e "${CYAN}║${NC}                ${BOLD}🤖 CLAUDE CODE BACKGROUND AGENTS${NC}                          ${YELLOW}🔔 NOTIFY ON${NC}             ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}                         ${BOLD}🤖 CLAUDE CODE BACKGROUND AGENTS${NC}                                            ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"

    if [ -d "$AGENT_DIR" ]; then
        agent_count=0
        running_count=0

        # Table header - wider TASK column
        printf "${CYAN}║${NC} %-28s ${CYAN}│${NC} %-10s ${CYAN}│${NC} %-8s ${CYAN}│${NC} %-7s ${CYAN}│${NC} %-12s ${CYAN}│${NC} %-14s ${CYAN}║${NC}\n" \
            "TASK" "PROJECT" "STATUS" "TIME" "PROGRESS" "ACTION"
        echo -e "${CYAN}╠══════════════════════════════╪════════════╪══════════╪═════════╪══════════════╪════════════════╣${NC}"

        while IFS= read -r output_file; do
            [ -z "$output_file" ] && continue
            agent_count=$((agent_count + 1))
            agent_id=$(basename "$output_file" .output)

            # Get task info - wider title
            task_title=$(get_task_title "$agent_id")
            [ -z "$task_title" ] && task_title="${agent_id:0:10}..."
            task_title="${task_title:0:26}"

            # Get project name
            project_name=$(get_project_name "$output_file")
            project_name="${project_name:0:10}"

            # Get progress info
            IFS='|' read -r tool_count last_tool last_text <<< "$(get_progress_info "$output_file")"
            [ -z "$tool_count" ] && tool_count="0"
            [ -z "$last_tool" ] && last_tool="-"
            last_tool="${last_tool:0:12}"

            # Get elapsed time
            elapsed=$(get_elapsed "$agent_id" "$output_file")

            # Status and display
            if is_running "$output_file"; then
                running_count=$((running_count + 1))
                spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
                spinner_index=$(($(date +%s) % 10))
                spinner="${spinner_chars:$spinner_index:1}"

                # Print running row
                printf "${CYAN}║${NC} ${BOLD}%-26s${NC} ${CYAN}│${NC} ${MAGENTA}%-10s${NC} ${CYAN}│${NC} ${GREEN}%s %-6s${NC} ${CYAN}│${NC} %-7s ${CYAN}│${NC} " \
                    "$task_title" "$project_name" "$spinner" "RUN" "$elapsed"
                progress_bar "$tool_count"
                printf " ${CYAN}│${NC} ${BLUE}%-14s${NC} ${CYAN}║${NC}\n" "$last_tool"
            else
                # Print done row
                printf "${CYAN}║${NC} ${DIM}%-26s${NC} ${CYAN}│${NC} ${DIM}%-10s${NC} ${CYAN}│${NC} ${YELLOW}✓ %-6s${NC} ${CYAN}│${NC} ${DIM}%-7s${NC} ${CYAN}│${NC} " \
                    "$task_title" "$project_name" "DONE" "$elapsed"
                progress_bar "$tool_count"
                printf " ${CYAN}│${NC} ${DIM}%-14s${NC} ${CYAN}║${NC}\n" "-"
            fi

            # Add spacing between rows
            echo -e "${CYAN}║${NC}                              ${CYAN}│${NC}            ${CYAN}│${NC}          ${CYAN}│${NC}         ${CYAN}│${NC}              ${CYAN}│${NC}                ${CYAN}║${NC}"

        done < <(find "$AGENT_DIR" -name "*.output" -mmin -30 2>/dev/null | xargs ls -t 2>/dev/null | head -6)

        if [ $agent_count -eq 0 ]; then
            echo -e "${CYAN}║${NC}                                                                                                     ${CYAN}║${NC}"
            printf "${CYAN}║${NC}        ${YELLOW}No recent agents.${NC} Launch one with: ${BOLD}/bga <task>${NC}                                             ${CYAN}║${NC}\n"
            echo -e "${CYAN}║${NC}                                                                                                     ${CYAN}║${NC}"
        fi

        # Summary
        echo -e "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
        printf "${CYAN}║${NC}  ${BOLD}SUMMARY:${NC} ${GREEN}● %d running${NC}   ${YELLOW}○ %d completed${NC}   ${DIM}Total: %d${NC}                                                 ${CYAN}║${NC}\n" \
            "$running_count" "$((agent_count - running_count))" "$agent_count"
    else
        echo -e "${CYAN}║${NC}  ${YELLOW}No agent directory found.${NC}                                                                         ${CYAN}║${NC}"
    fi

    # Footer
    echo -e "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${NC}  ${DIM}%s${NC}   │   ${DIM}Refresh: %ss${NC}   │   ${DIM}Kill: agents kill <id>${NC}   │   ${DIM}Ctrl+C exit${NC}                       ${CYAN}║${NC}\n" \
        "$(date '+%H:%M:%S')" "$REFRESH_RATE"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"
}

watch_agents() {
    local notify_mode="${1:-false}"
    [ "$notify_mode" = "true" ] && save_state
    while true; do
        [ "$notify_mode" = "true" ] && check_completions
        show_status "$notify_mode"
        sleep $REFRESH_RATE
    done
}

kill_agent() {
    local agent_id="$1"
    if [ -z "$agent_id" ]; then
        echo -e "${BOLD}Usage:${NC} agents kill <agent_id>"
        echo ""
        echo "Running agents:"
        list_agents
        return 1
    fi

    # Find processes related to this agent
    local pids=$(pgrep -f "$agent_id" 2>/dev/null)

    if [ -n "$pids" ]; then
        echo -e "${YELLOW}Killing agent $agent_id...${NC}"
        echo "$pids" | xargs kill 2>/dev/null

        # Update meta file
        local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
        if [ -f "$meta_file" ]; then
            echo "STATUS: KILLED" >> "$meta_file"
        fi

        echo -e "${GREEN}✓ Agent killed${NC}"
    else
        echo -e "${YELLOW}No running process found for agent $agent_id${NC}"
        echo "It may have already completed."
    fi
}

list_agents() {
    echo -e "${BOLD}Background Agents (last 60 min):${NC}"
    echo ""

    if [ -d "$AGENT_DIR" ]; then
        found=0
        running=0
        while IFS= read -r output_file; do
            [ -z "$output_file" ] && continue
            found=$((found + 1))
            agent_id=$(basename "$output_file" .output)
            task_title=$(get_task_title "$agent_id")
            elapsed=$(get_elapsed "$agent_id" "$output_file")

            if is_running "$output_file"; then
                running=$((running + 1))
                if [ -n "$task_title" ]; then
                    echo -e "  ${GREEN}●${NC} ${BOLD}${task_title}${NC} ${DIM}(${agent_id})${NC} - ${elapsed}"
                else
                    echo -e "  ${GREEN}●${NC} ${agent_id} - ${elapsed}"
                fi
            else
                if [ -n "$task_title" ]; then
                    echo -e "  ${YELLOW}○${NC} ${task_title} ${DIM}(${agent_id})${NC}"
                else
                    echo -e "  ${YELLOW}○${NC} ${agent_id}"
                fi
            fi
        done < <(find "$AGENT_DIR" -name "*.output" -mmin -60 2>/dev/null | xargs ls -t 2>/dev/null)

        if [ $found -eq 0 ]; then
            echo "  No recent agents"
        else
            echo ""
            echo -e "  ${GREEN}●${NC} = running  ${YELLOW}○${NC} = done"
            echo -e "  Total: $found ($running running)"
        fi
    else
        echo "  No agent directory"
    fi
}

tail_agent() {
    local agent_id="$1"
    if [ -z "$agent_id" ]; then
        echo "Usage: agents tail <agent_id>"
        return 1
    fi

    output_file=$(find "$AGENT_DIR" -name "${agent_id}*.output" 2>/dev/null | head -1)

    if [ -f "$output_file" ]; then
        task_title=$(get_task_title "$agent_id")
        if [ -n "$task_title" ]; then
            echo -e "${BOLD}📋 $task_title${NC}"
        else
            echo -e "${BOLD}📋 Agent: $agent_id${NC}"
        fi
        echo -e "${CYAN}─────────────────────────────────────────────────────${NC}"
        tail -f "$output_file"
    else
        echo "Agent not found: $agent_id"
        echo "Try: agents list"
        return 1
    fi
}

notify_daemon() {
    echo "🔔 Notification daemon started"
    save_state
    while true; do
        check_completions
        sleep $REFRESH_RATE
    done
}

test_notify() {
    send_notification "🤖 Test" "Notifications working!"
    echo "Sent test notification"
}

cleanup() {
    echo -e "${BOLD}Cleaning up...${NC}"
    local count=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        rm "$f" 2>/dev/null
        count=$((count + 1))
    done < <(find "$AGENT_DIR" -name "*.output" -mmin +120 2>/dev/null)
    find "$META_DIR" -name "agent-meta-*.txt" -mmin +120 -delete 2>/dev/null
    echo "Cleaned $count old files"
}

launch_tmux_dashboard() {
    if ! command -v tmux &> /dev/null; then
        echo "tmux not installed. Run: brew install tmux"
        return 1
    fi
    if [ -n "$TMUX" ]; then
        tmux split-window -h -p 40 "bash $0 n"
    else
        tmux new-session -d -s agents "bash $0 n"
        tmux split-window -h -p 60
        tmux select-pane -L
        tmux attach-session -t agents
    fi
}

# Main
case "${1:-status}" in
    n|wn)
        watch_agents true
        ;;
    watch)
        if [ "$2" = "--notify" ] || [ "$2" = "-n" ]; then
            watch_agents true
        else
            watch_agents false
        fi
        ;;
    kill|k)
        kill_agent "$2"
        ;;
    tmux)
        launch_tmux_dashboard
        ;;
    status|s)
        show_status
        ;;
    list|l)
        list_agents
        ;;
    tail|t)
        tail_agent "$2"
        ;;
    notify)
        notify_daemon
        ;;
    test)
        test_notify
        ;;
    cleanup|clean)
        cleanup
        ;;
    *)
        echo -e "${BOLD}🤖 Agent Monitor${NC} - Dashboard for Claude Code background agents"
        echo ""
        echo "Usage: agents [command]"
        echo ""
        echo "Commands:"
        echo "  ${BOLD}n${NC}              Watch + notifications (recommended)"
        echo "  ${BOLD}status${NC}         Show current status"
        echo "  ${BOLD}list${NC}           List all recent agents"
        echo "  ${BOLD}tail <id>${NC}      Follow agent output"
        echo "  ${BOLD}kill <id>${NC}      Kill a running agent"
        echo "  ${BOLD}tmux${NC}           Launch split-screen dashboard"
        echo "  ${BOLD}test${NC}           Test notifications"
        echo "  ${BOLD}cleanup${NC}        Remove old agent files"
        ;;
esac
