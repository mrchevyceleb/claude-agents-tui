# Background Agent (/bga)

Launch a background agent to handle a task autonomously while you continue working.

## Usage

```
/bga <task description>
```

## Process

1. Take the task description provided
2. Create a short 3-5 word title for the task
3. Launch a background agent using the Task tool with `run_in_background: true`
4. Save task metadata for the monitor dashboard
5. Confirm launch to user with brief acknowledgment

## Instructions

When user runs `/bga <task>`:

1. Parse the task description and create a SHORT title (3-5 words max)
   - "scrape the pricing page" → "Scrape pricing page"
   - "research competitors in AI" → "Research AI competitors"
   - "fix the login bug" → "Fix login bug"

2. Launch the background agent with Task tool:
   - `subagent_type`: "general-purpose"
   - `run_in_background`: true
   - `prompt`: The user's full task description
   - `description`: Your short 3-5 word title

3. **CRITICAL**: After the Task tool returns, you MUST extract the agent_id from the output_file path and create a metadata file. The agent_id is the filename without extension (e.g., "a17e914" from "C:\...\tasks\a17e914.output").

   Create metadata file using Bash:

   **On Windows (PowerShell):**
   ```powershell
   $agentId = "[agent_id_from_output_file]"
   @"
TITLE: [your short title]
STARTED: $(Get-Date -Format 'HH:mm:ss')
TASK: [first 100 chars of task]
"@ | Out-File -FilePath "$env:TEMP\agent-meta-$agentId.txt" -Encoding utf8 -NoNewline
   ```

   **On macOS/Linux:**
   ```bash
   cat > /tmp/agent-meta-[agent_id].txt << 'EOF'
TITLE: [your short title]
STARTED: $(date '+%H:%M:%S')
TASK: [first 100 chars of task]
EOF
   ```

   **Important**: Always verify the agent_id was extracted correctly before creating the metadata file. If the Task tool doesn't return an output_file, the metadata creation will fail.

4. Respond with brief confirmation:
   ```
   🚀 Agent launched: [short title]
   ```

5. Do NOT wait for the agent to complete - continue conversation normally

## Examples

**User:** `/bga scrape the pricing page at example.com and summarize it`
```
🚀 Agent launched: Scrape pricing page
```

**User:** `/bga research competitors in the AI avatar space`
```
🚀 Agent launched: Research AI competitors
```

**User:** `/bga refactor the utils folder to use TypeScript`
```
🚀 Agent launched: Refactor to TypeScript
```

## Notes

- Background agents run independently and don't block the conversation
- Results are delivered when the agent completes
- Metadata is saved so the `agents` dashboard can show task titles
- Use for tasks that take time but don't need immediate results
- Great for: research, scraping, refactoring, documentation, analysis
