#!/bin/bash
# Agent Monitor v2.0 - Visual dashboard for Claude Code background agents
# Usage: agent-monitor.sh [watch|status|list|kill|tail|help]

AGENT_DIR="/private/tmp/claude"
META_DIR="/tmp"
STATE_FILE="/tmp/agent-monitor-state"
COMPLETIONS_FILE="/tmp/agent-completions.txt"

# View state (global variables)
REFRESH_RATE=2
NOTIFY_ON=false
FILTER_MODE="ALL"  # ALL, RUNNING, FINISHED
CURRENT_PAGE=0
PAGE_SIZE=10
DETAIL_MODE=false

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

# macOS notification with sound
send_notification() {
    local title="$1"
    local message="$2"
    local is_failure="${3:-false}"

    # Choose sound based on success/failure
    local sound="Glass"
    [ "$is_failure" = "true" ] && sound="Basso"

    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "$title" -message "$message" -sound "$sound" -ignoreDnD
    elif [ -f /opt/homebrew/bin/terminal-notifier ]; then
        /opt/homebrew/bin/terminal-notifier -title "$title" -message "$message" -sound "$sound" -ignoreDnD
    else
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\""
    fi

    # Also play system sound
    if [ "$is_failure" = "true" ]; then
        afplay /System/Library/Sounds/Basso.aiff &>/dev/null &
    else
        afplay /System/Library/Sounds/Glass.aiff &>/dev/null &
    fi
}

is_running() {
    local file="$1"
    [ "$(find "$file" -mmin -1 2>/dev/null)" ]
}

get_task_title() {
    local agent_id="$1"
    local output_file="$2"

    # First try metadata file
    local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
    if [ -f "$meta_file" ]; then
        local title=$(grep "^TITLE:" "$meta_file" 2>/dev/null | sed 's/^TITLE: //')
        if [ -n "$title" ]; then
            echo "$title"
            return
        fi
    fi

    # Get project name for later use
    local project_name="Task"
    if [ -n "$output_file" ] && [ -f "$output_file" ]; then
        local project_path=$(dirname "$(dirname "$output_file")")
        local folder_name=$(basename "$project_path")

        # Clean up folder name: remove leading dashes and drive prefix
        local clean_name=$(echo "$folder_name" | sed 's/^-*//' | sed 's/^[A-Z]--//')

        # Get the last meaningful segment
        project_name=$(echo "$clean_name" | rev | cut -d'-' -f1 | rev)
        if [ ${#project_name} -le 2 ]; then
            # Try second to last segment
            project_name=$(echo "$clean_name" | rev | cut -d'-' -f2 | rev)
        fi
    fi

    # Try to detect task type from output content
    if [ -n "$output_file" ] && [ -f "$output_file" ]; then
        local content=$(head -50 "$output_file" 2>/dev/null)

        # Detect dev server
        if echo "$content" | grep -qiE "VITE|vite|Vite.*ready|localhost:[0-9]+|dev server|HMR"; then
            echo "$project_name Dev Server"
            return
        fi

        # Detect build process
        if echo "$content" | grep -qiE "build|Building|compiled|webpack|rollup|esbuild"; then
            echo "$project_name Build"
            return
        fi

        # Detect test runner
        if echo "$content" | grep -qiE "test|jest|vitest|mocha|PASS|FAIL|spec\."; then
            echo "$project_name Tests"
            return
        fi

        # Detect linting
        if echo "$content" | grep -qiE "eslint|lint|prettier|formatting"; then
            echo "$project_name Lint"
            return
        fi

        # Detect deployment
        if echo "$content" | grep -qiE "deploy|vercel|netlify|supabase|firebase"; then
            echo "$project_name Deploy"
            return
        fi

        # Detect database operations
        if echo "$content" | grep -qiE "migration|database|SQL|prisma|drizzle"; then
            echo "$project_name Database"
            return
        fi

        # Detect git operations
        if echo "$content" | grep -qiE "git |commit|push|pull|merge|branch"; then
            echo "$project_name Git"
            return
        fi

        # Detect install/dependency operations
        if echo "$content" | grep -qiE "npm install|pnpm|yarn add|installing|dependencies"; then
            echo "$project_name Install"
            return
        fi

        # Look for tool_use patterns to detect activity type
        local last_tool=$(tail -30 "$output_file" 2>/dev/null | grep -o '"name":"[^"]*"' | tail -1 | sed 's/"name":"//;s/"//')
        if [ -n "$last_tool" ]; then
            case "$last_tool" in
                Read|Glob|Grep) echo "$project_name Explore"; return ;;
                Edit|Write) echo "$project_name Edit"; return ;;
                Bash) echo "$project_name Shell"; return ;;
                WebFetch|WebSearch) echo "$project_name Research"; return ;;
                Task) echo "$project_name Subtask"; return ;;
            esac
        fi
    fi

    # Ultimate fallback: project name + start time to distinguish multiple tasks
    if [ -n "$project_name" ] && [ "$project_name" != "Task" ]; then
        # Try to get start time from metadata
        local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
        local start_time=""
        if [ -f "$meta_file" ]; then
            start_time=$(grep "^STARTED:" "$meta_file" 2>/dev/null | sed 's/^STARTED: //' | cut -d':' -f1-2)
        fi

        # If we have start time, use it to make the title more specific
        if [ -n "$start_time" ]; then
            echo "$project_name $start_time"
            return
        fi

        # If no start time, use file modification time
        if [ -n "$output_file" ] && [ -f "$output_file" ]; then
            local file_time=$(stat -f "%Sm" -t "%H:%M" "$output_file" 2>/dev/null)
            if [ -n "$file_time" ]; then
                echo "$project_name $file_time"
                return
            fi
        fi

        # Absolute fallback
        echo "$project_name work"
        return
    fi

    # Final fallback: truncated ID
    echo "${agent_id:0:8}..."
}

get_start_time() {
    local agent_id="$1"
    local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
    if [ -f "$meta_file" ]; then
        grep "^STARTED:" "$meta_file" 2>/dev/null | sed 's/^STARTED: //'
    fi
}

# Get agent status: RUNNING, SUCCESS, FAILED, KILLED
get_agent_status() {
    local output_file="$1"
    local agent_id="$2"

    # Check if still running
    if is_running "$output_file"; then
        echo "RUNNING"
        return
    fi

    # Check if killed
    local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
    if [ -f "$meta_file" ]; then
        if grep -q "STATUS: KILLED" "$meta_file" 2>/dev/null; then
            echo "KILLED"
            return
        fi
    fi

    # Check for errors in output (last 100 lines)
    if [ -f "$output_file" ]; then
        local tail_content=$(tail -100 "$output_file" 2>/dev/null)
        if echo "$tail_content" | grep -qiE "(error:|exception:|fatal:|failed to|cannot |FAILED)"; then
            echo "FAILED"
            return
        fi
    fi

    echo "SUCCESS"
}

# Get completion time for finished agents
get_completion_time() {
    local agent_id="$1"

    if [ -f "$COMPLETIONS_FILE" ]; then
        local entry=$(grep "^$agent_id|" "$COMPLETIONS_FILE" 2>/dev/null)
        if [ -n "$entry" ]; then
            echo "$entry" | cut -d'|' -f2
        fi
    fi
}

# Save completion time when agent finishes
save_completion_time() {
    local agent_id="$1"
    local elapsed="$2"

    # Check if already saved
    if [ -f "$COMPLETIONS_FILE" ]; then
        if grep -q "^$agent_id|" "$COMPLETIONS_FILE" 2>/dev/null; then
            return
        fi
    fi

    echo "$agent_id|$elapsed" >> "$COMPLETIONS_FILE"
}

# Calculate elapsed time from start
get_elapsed() {
    local agent_id="$1"
    local output_file="$2"
    local for_display="${3:-false}"

    # For completed agents, try to get saved completion time
    if ! is_running "$output_file" && [ "$for_display" = "true" ]; then
        local saved_time=$(get_completion_time "$agent_id")
        if [ -n "$saved_time" ]; then
            echo "$saved_time"
            return
        fi
    fi

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
            local result=$(printf "%dm %02ds" $mins $secs)

            # Save for completed agents
            if ! is_running "$output_file"; then
                save_completion_time "$agent_id" "$result"
            fi

            echo "$result"
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
    for ((i=0; i<filled; i++)); do printf "#"; done
    printf "${DIM}"
    for ((i=0; i<empty; i++)); do printf "."; done
    printf "${NC}"
}

get_progress_info() {
    local output_file="$1"
    local tool_count=$(grep -c '"tool_use"\|"tool_result"' "$output_file" 2>/dev/null || echo "0")
    local last_tool=$(grep -o '"name":"[^"]*"' "$output_file" 2>/dev/null | tail -1 | sed 's/"name":"//;s/"//' | head -c 15)
    echo "${tool_count}|${last_tool}"
}

# Extract project name from output file path
get_project_name() {
    local output_file="$1"
    local dir_path=$(dirname "$(dirname "$output_file")")
    local folder_name=$(basename "$dir_path")

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
            # Find the output file for this agent
            local output_file=$(find "$AGENT_DIR" -name "${agent_id}.output" 2>/dev/null | head -1)
            local status=$(get_agent_status "$output_file" "$agent_id")
            local title=$(get_task_title "$agent_id" "$output_file")

            if [ "$status" = "FAILED" ]; then
                send_notification "Agent Failed" "$title" true
            elif [ "$status" = "KILLED" ]; then
                send_notification "Agent Killed" "$title" false
            else
                send_notification "Agent Complete" "$title" false
            fi
        fi
    done
    echo "$current" > "$STATE_FILE"
}

# Copy agent ID to clipboard
copy_agent_id() {
    local agent_id="$1"
    if [ -n "$agent_id" ]; then
        echo -n "$agent_id" | pbcopy
        return 0
    fi
    return 1
}

# Show quick view of agent output
show_quick_view() {
    local output_file="$1"
    local agent_id="$2"

    if [ ! -f "$output_file" ]; then
        return
    fi

    local title=$(get_task_title "$agent_id" "$output_file")

    echo ""
    echo -e "${CYAN}┌─ Quick View: ${BOLD}$title${NC} ${CYAN}─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}"

    # Show last 10 lines
    tail -10 "$output_file" 2>/dev/null | while IFS= read -r line; do
        # Truncate long lines
        local truncated="${line:0:95}"
        printf "${CYAN}│${NC} %s\n" "$truncated"
    done

    echo -e "${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────────────────────────────────┘${NC}"
}

# Show detailed agent info
show_agent_details() {
    local output_file="$1"
    local agent_id="$2"

    if [ ! -f "$output_file" ]; then
        return
    fi

    local title=$(get_task_title "$agent_id" "$output_file")
    local project=$(get_project_name "$output_file")
    local status=$(get_agent_status "$output_file" "$agent_id")
    local elapsed=$(get_elapsed "$agent_id" "$output_file" true)
    local tool_count=$(grep -c '"tool_use"\|"tool_result"' "$output_file" 2>/dev/null || echo "0")

    # Get task description from metadata
    local task_desc=""
    local meta_file="${META_DIR}/agent-meta-${agent_id}.txt"
    if [ -f "$meta_file" ]; then
        task_desc=$(grep "^TASK:" "$meta_file" 2>/dev/null | sed 's/^TASK: //')
    fi

    # Get last 5 tools used
    local last_tools=$(grep -o '"name":"[^"]*"' "$output_file" 2>/dev/null | tail -5 | sed 's/"name":"//;s/"//' | tr '\n' ', ' | sed 's/,$//')

    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                              ${BOLD}AGENT DETAILS${NC}                                                       ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    printf "${CYAN}║${NC}  ${BOLD}Title:${NC}       %-80s ${CYAN}║${NC}\n" "$title"
    printf "${CYAN}║${NC}  ${BOLD}Agent ID:${NC}    %-80s ${CYAN}║${NC}\n" "$agent_id"
    printf "${CYAN}║${NC}  ${BOLD}Project:${NC}     %-80s ${CYAN}║${NC}\n" "$project"
    echo -e "${CYAN}║${NC}"

    # Status with color
    case "$status" in
        RUNNING) printf "${CYAN}║${NC}  ${BOLD}Status:${NC}      ${GREEN}* RUNNING${NC}%-72s ${CYAN}║${NC}\n" "" ;;
        SUCCESS) printf "${CYAN}║${NC}  ${BOLD}Status:${NC}      ${GREEN}V SUCCESS${NC}%-72s ${CYAN}║${NC}\n" "" ;;
        FAILED)  printf "${CYAN}║${NC}  ${BOLD}Status:${NC}      ${RED}X FAILED${NC}%-73s ${CYAN}║${NC}\n" "" ;;
        KILLED)  printf "${CYAN}║${NC}  ${BOLD}Status:${NC}      ${YELLOW}! KILLED${NC}%-73s ${CYAN}║${NC}\n" "" ;;
    esac

    printf "${CYAN}║${NC}  ${BOLD}Elapsed:${NC}     %-80s ${CYAN}║${NC}\n" "$elapsed"
    printf "${CYAN}║${NC}  ${BOLD}Tool Count:${NC}  %-80s ${CYAN}║${NC}\n" "$tool_count"
    echo -e "${CYAN}║${NC}"

    if [ -n "$task_desc" ]; then
        printf "${CYAN}║${NC}  ${BOLD}Task:${NC}        %-80s ${CYAN}║${NC}\n" "${task_desc:0:80}"
    fi

    if [ -n "$last_tools" ]; then
        printf "${CYAN}║${NC}  ${BOLD}Last Tools:${NC}  %-80s ${CYAN}║${NC}\n" "${last_tools:0:80}"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Press any key to return...                                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════════════════════════════════╝${NC}"

    read -n 1 -s
}

show_status() {
    clear

    # Build filtered file list
    local all_files=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        all_files+=("$f")
    done < <(find "$AGENT_DIR" -name "*.output" -mmin -60 2>/dev/null | xargs ls -t 2>/dev/null)

    # Apply filter
    local filtered_files=()
    for f in "${all_files[@]}"; do
        local is_run=$(is_running "$f" && echo "yes" || echo "no")
        case "$FILTER_MODE" in
            RUNNING)
                [ "$is_run" = "yes" ] && filtered_files+=("$f")
                ;;
            FINISHED)
                [ "$is_run" = "no" ] && filtered_files+=("$f")
                ;;
            *)
                filtered_files+=("$f")
                ;;
        esac
    done

    local total_filtered=${#filtered_files[@]}
    local total_pages=$(( (total_filtered + PAGE_SIZE - 1) / PAGE_SIZE ))
    [ $total_pages -lt 1 ] && total_pages=1
    [ $CURRENT_PAGE -ge $total_pages ] && CURRENT_PAGE=$((total_pages - 1))
    [ $CURRENT_PAGE -lt 0 ] && CURRENT_PAGE=0

    local start_idx=$((CURRENT_PAGE * PAGE_SIZE))
    local end_idx=$((start_idx + PAGE_SIZE))
    [ $end_idx -gt $total_filtered ] && end_idx=$total_filtered

    # Header
    echo -e "${CYAN}+============================================================================================================+${NC}"
    echo -e "${CYAN}|${NC}                              ${BOLD}CLAUDE CODE BACKGROUND AGENTS${NC}                                             ${CYAN}|${NC}"
    echo -e "${CYAN}+------------------------------------------------------------------------------------------------------------+${NC}"

    # Shortcuts bar
    local notify_status="OFF"
    [ "$NOTIFY_ON" = "true" ] && notify_status="ON"
    printf "${CYAN}|${NC}  [N] Notify: %-3s   [R/F/A] Filter: %-8s   [+/-] Speed: %ds   [C] Copy   [Q] Quit               ${CYAN}|${NC}\n" \
        "$notify_status" "$FILTER_MODE" "$REFRESH_RATE"
    echo -e "${CYAN}|${NC}  [1-9] Quick view   [D]+[1-9] Details   [PgUp/PgDn] Page                                            ${CYAN}|${NC}"
    echo -e "${CYAN}+============================================================================================================+${NC}"

    if [ -d "$AGENT_DIR" ]; then
        local running_count=0
        local success_count=0
        local failed_count=0

        # Table header
        printf "${CYAN}|${NC} # ${CYAN}|${NC} %-26s ${CYAN}|${NC} %-10s ${CYAN}|${NC} %-10s ${CYAN}|${NC} %-9s ${CYAN}|${NC} %-12s ${CYAN}|${NC} %-12s ${CYAN}|${NC}\n" \
            "TASK" "PROJECT" "STATUS" "TIME" "PROGRESS" "ACTION"
        echo -e "${CYAN}+===+============================+============+============+===========+==============+==============+${NC}"

        # Count totals from all files
        for f in "${all_files[@]}"; do
            local aid=$(basename "$f" .output)
            local st=$(get_agent_status "$f" "$aid")
            case "$st" in
                RUNNING) running_count=$((running_count + 1)) ;;
                SUCCESS) success_count=$((success_count + 1)) ;;
                FAILED|KILLED) failed_count=$((failed_count + 1)) ;;
            esac
        done

        # Display current page
        local display_num=1
        for ((i=start_idx; i<end_idx; i++)); do
            local output_file="${filtered_files[$i]}"
            [ -z "$output_file" ] && continue

            local agent_id=$(basename "$output_file" .output)
            local task_title=$(get_task_title "$agent_id" "$output_file")
            task_title="${task_title:0:24}"

            local project_name=$(get_project_name "$output_file")
            project_name="${project_name:0:10}"

            IFS='|' read -r tool_count last_tool <<< "$(get_progress_info "$output_file")"
            [ -z "$tool_count" ] && tool_count="0"
            [ -z "$last_tool" ] && last_tool="-"
            last_tool="${last_tool:0:10}"

            local elapsed=$(get_elapsed "$agent_id" "$output_file" true)
            local status=$(get_agent_status "$output_file" "$agent_id")

            # Format status display
            local status_display=""
            local status_color=""
            case "$status" in
                RUNNING)
                    status_display="* RUNNING"
                    status_color="${GREEN}"
                    ;;
                SUCCESS)
                    status_display="V SUCCESS"
                    status_color="${GREEN}"
                    ;;
                FAILED)
                    status_display="X FAILED"
                    status_color="${RED}"
                    ;;
                KILLED)
                    status_display="! KILLED"
                    status_color="${YELLOW}"
                    ;;
            esac

            # Build progress bar string
            local prog_bar=$(progress_bar "$tool_count")

            # Print row
            printf "${CYAN}|${NC} %d ${CYAN}|${NC} %-26s ${CYAN}|${NC} %-10s ${CYAN}|${NC} ${status_color}%-10s${NC} ${CYAN}|${NC} %-9s ${CYAN}|${NC} " \
                "$display_num" "$task_title" "$project_name" "$status_display" "$elapsed"
            echo -ne "$prog_bar"
            printf " ${CYAN}|${NC} %-12s ${CYAN}|${NC}\n" "$last_tool"

            display_num=$((display_num + 1))
        done

        if [ ${#filtered_files[@]} -eq 0 ]; then
            echo -e "${CYAN}|${NC}                                                                                                            ${CYAN}|${NC}"
            printf "${CYAN}|${NC}        ${YELLOW}No agents match filter.${NC} Launch one with: ${BOLD}/bga <task>${NC}                                          ${CYAN}|${NC}\n"
            echo -e "${CYAN}|${NC}                                                                                                            ${CYAN}|${NC}"
        fi

        # Summary
        local done_count=$((success_count + failed_count))
        echo -e "${CYAN}+============================================================================================================+${NC}"
        printf "${CYAN}|${NC}  ${BOLD}SUMMARY:${NC} ${GREEN}* %d running${NC}   ${YELLOW}o %d done${NC} (${GREEN}%dV${NC} ${RED}%dX${NC})   Total: %d   Page %d/%d                            ${CYAN}|${NC}\n" \
            "$running_count" "$done_count" "$success_count" "$failed_count" "${#all_files[@]}" "$((CURRENT_PAGE + 1))" "$total_pages"
    else
        echo -e "${CYAN}|${NC}  ${YELLOW}No agent directory found.${NC}                                                                               ${CYAN}|${NC}"
    fi

    # Footer
    echo -e "${CYAN}+============================================================================================================+${NC}"
    printf "${CYAN}|${NC}  %-8s  |  Refresh: %ds  |  Launch: /bga <task>  |  Kill: agents kill <id>                     ${CYAN}|${NC}\n" \
        "$(date '+%H:%M:%S')" "$REFRESH_RATE"
    echo -e "${CYAN}+============================================================================================================+${NC}"
}

watch_agents() {
    # Initialize
    [ "$NOTIFY_ON" = "true" ] && save_state

    # Set up terminal for non-blocking input
    stty -echo -icanon time 0 min 0

    # Cleanup on exit
    trap 'stty echo icanon; exit' INT TERM EXIT

    local last_refresh=$(date +%s)
    local detail_next=false

    while true; do
        local now=$(date +%s)

        # Check for key press
        local key=$(dd bs=1 count=1 2>/dev/null)

        if [ -n "$key" ]; then
            case "$key" in
                q|Q)
                    stty echo icanon
                    clear
                    exit 0
                    ;;
                n|N)
                    if [ "$NOTIFY_ON" = "true" ]; then
                        NOTIFY_ON=false
                    else
                        NOTIFY_ON=true
                        save_state
                    fi
                    last_refresh=0
                    ;;
                r|R)
                    FILTER_MODE="RUNNING"
                    CURRENT_PAGE=0
                    last_refresh=0
                    ;;
                f|F)
                    FILTER_MODE="FINISHED"
                    CURRENT_PAGE=0
                    last_refresh=0
                    ;;
                a|A)
                    FILTER_MODE="ALL"
                    CURRENT_PAGE=0
                    last_refresh=0
                    ;;
                +|=)
                    REFRESH_RATE=$((REFRESH_RATE + 1))
                    [ $REFRESH_RATE -gt 10 ] && REFRESH_RATE=10
                    last_refresh=0
                    ;;
                -|_)
                    REFRESH_RATE=$((REFRESH_RATE - 1))
                    [ $REFRESH_RATE -lt 1 ] && REFRESH_RATE=1
                    last_refresh=0
                    ;;
                c|C)
                    # Copy first running agent ID
                    local first_running=$(find "$AGENT_DIR" -name "*.output" -mmin -1 2>/dev/null | head -1)
                    if [ -n "$first_running" ]; then
                        local aid=$(basename "$first_running" .output)
                        copy_agent_id "$aid"
                    fi
                    last_refresh=0
                    ;;
                d|D)
                    detail_next=true
                    ;;
                [1-9])
                    local idx=$((key - 1))
                    local files=()
                    while IFS= read -r f; do
                        [ -z "$f" ] && continue
                        files+=("$f")
                    done < <(find "$AGENT_DIR" -name "*.output" -mmin -60 2>/dev/null | xargs ls -t 2>/dev/null | head -$PAGE_SIZE)

                    if [ $idx -lt ${#files[@]} ]; then
                        local selected="${files[$idx]}"
                        local aid=$(basename "$selected" .output)

                        if [ "$detail_next" = "true" ]; then
                            show_agent_details "$selected" "$aid"
                            detail_next=false
                        else
                            show_status
                            show_quick_view "$selected" "$aid"
                            sleep 3
                        fi
                    fi
                    detail_next=false
                    last_refresh=0
                    ;;
            esac
        fi

        # Refresh display periodically
        if [ $((now - last_refresh)) -ge $REFRESH_RATE ]; then
            [ "$NOTIFY_ON" = "true" ] && check_completions
            show_status
            last_refresh=$now
        fi

        sleep 0.1
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

        echo -e "${GREEN}V Agent killed${NC}"
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
        success=0
        failed=0

        while IFS= read -r output_file; do
            [ -z "$output_file" ] && continue
            found=$((found + 1))
            agent_id=$(basename "$output_file" .output)
            task_title=$(get_task_title "$agent_id" "$output_file")
            elapsed=$(get_elapsed "$agent_id" "$output_file" true)
            status=$(get_agent_status "$output_file" "$agent_id")

            case "$status" in
                RUNNING)
                    running=$((running + 1))
                    echo -e "  ${GREEN}*${NC} ${BOLD}${task_title}${NC} ${DIM}(${agent_id})${NC} - ${elapsed}"
                    ;;
                SUCCESS)
                    success=$((success + 1))
                    echo -e "  ${GREEN}V${NC} ${task_title} ${DIM}(${agent_id})${NC} - ${elapsed}"
                    ;;
                FAILED)
                    failed=$((failed + 1))
                    echo -e "  ${RED}X${NC} ${task_title} ${DIM}(${agent_id})${NC} - ${elapsed}"
                    ;;
                KILLED)
                    failed=$((failed + 1))
                    echo -e "  ${YELLOW}!${NC} ${task_title} ${DIM}(${agent_id})${NC} - ${elapsed}"
                    ;;
            esac
        done < <(find "$AGENT_DIR" -name "*.output" -mmin -60 2>/dev/null | xargs ls -t 2>/dev/null)

        if [ $found -eq 0 ]; then
            echo "  No recent agents"
        else
            echo ""
            echo -e "  ${GREEN}*${NC} = running  ${GREEN}V${NC} = success  ${RED}X${NC} = failed  ${YELLOW}!${NC} = killed"
            echo -e "  Total: $found ($running running, $success success, $failed failed)"
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
        task_title=$(get_task_title "$agent_id" "$output_file")
        echo -e "${BOLD}Task: $task_title${NC}"
        echo -e "${CYAN}-------------------------------------------------------${NC}"
        tail -f "$output_file"
    else
        echo "Agent not found: $agent_id"
        echo "Try: agents list"
        return 1
    fi
}

notify_daemon() {
    echo "Notification daemon started"
    save_state
    while true; do
        check_completions
        sleep $REFRESH_RATE
    done
}

test_notify() {
    echo "Testing success notification..."
    send_notification "Agent Complete" "Test task completed successfully" false
    sleep 2
    echo "Testing failure notification..."
    send_notification "Agent Failed" "Test task failed with errors" true
    echo "Done!"
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
    [ -f "$COMPLETIONS_FILE" ] && rm "$COMPLETIONS_FILE" 2>/dev/null
    echo "Cleaned $count old files"
}

show_help() {
    echo -e "${BOLD}Agent Monitor v2.0${NC} - Dashboard for Claude Code background agents"
    echo ""
    echo "Usage: agents [command]"
    echo ""
    echo "Commands:"
    echo "  ${BOLD}(default)${NC}      Start live dashboard"
    echo "  ${BOLD}n${NC}              Start with notifications enabled"
    echo "  ${BOLD}status${NC}         Show current status (one-time)"
    echo "  ${BOLD}list${NC}           List all recent agents"
    echo "  ${BOLD}tail <id>${NC}      Follow agent output"
    echo "  ${BOLD}kill <id>${NC}      Kill a running agent"
    echo "  ${BOLD}test${NC}           Test notifications"
    echo "  ${BOLD}cleanup${NC}        Remove old agent files"
    echo "  ${BOLD}help${NC}           Show this help"
    echo ""
    echo "Dashboard Keyboard Shortcuts:"
    echo "  ${BOLD}N${NC}              Toggle notifications on/off"
    echo "  ${BOLD}R/F/A${NC}          Filter: Running/Finished/All"
    echo "  ${BOLD}+/-${NC}            Adjust refresh rate (1-10s)"
    echo "  ${BOLD}C${NC}              Copy agent ID to clipboard"
    echo "  ${BOLD}1-9${NC}            Quick view agent output"
    echo "  ${BOLD}D+1-9${NC}          Show full agent details"
    echo "  ${BOLD}PgUp/PgDn${NC}      Navigate pages"
    echo "  ${BOLD}Q${NC}              Quit dashboard"
}

# Main
case "${1:-watch}" in
    n|wn)
        NOTIFY_ON=true
        watch_agents
        ;;
    watch|w)
        if [ "$2" = "--notify" ] || [ "$2" = "-n" ]; then
            NOTIFY_ON=true
        fi
        watch_agents
        ;;
    kill|k)
        kill_agent "$2"
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
    help|h|--help|-h)
        show_help
        ;;
    *)
        show_help
        ;;
esac
