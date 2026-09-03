# Bob Shell CLI Reference

Generated from `bob --help`, `bob chat --help`, `bob run --help`.

---

## Top-level: `bob [options] [command]`

| Flag | Description |
|------|-------------|
| `-v, --version` | Show current version number |
| `-p, --prompt <prompt>` | Prompt to send to the agent (non-interactive) |
| `-r, --resume [task-id]` | Open the resume picker, or resume a specific task id |
| `--list-tasks [limit]` | List available tasks (optional: number or `'all'`, default 20) |
| `--show-license` | Show full paths to license files for review |
| `--accept-license` | Accept the IBM license agreement and continue |
| `-h, --help` | Display help |

### Subcommands

| Command | Description |
|---------|-------------|
| `chat` | Launch the interactive terminal UI client |
| `run` | Execute a single task in headless mode |
| `mcp` | Manage MCP server configurations |
| `acp` | Start Bob Shell as an Agent Client Protocol server |

---

## `bob chat [options]`

Launch the interactive terminal UI.

| Flag | Description |
|------|-------------|
| `--instance-id <id>` | Select an instance for the session in advance |
| `--auto-approve` | Automatically approve all tool executions without prompting |
| `-w, --workspace <path>` | Workspace directory |
| `--mode <mode>` | Mode to use — built-in or custom mode slug (default: `agent`) |
| `--max-cost <number>` | Maximum total cost limit |
| `--max-turns <number>` | Maximum number of turns limit |
| `--log-level <level>` | Log level: `debug`, `info`, `warn`, `error`, `silent` (or `BOB_LOG_LEVEL` env var) |
| `--disable-mcp` | Disable MCP server initialization |
| `--disable-subagents` | Disable subagent tool registration |
| `--trust` | Mark the current folder as trusted |
| `-r, --resume [task-id]` | Open the resume picker, or resume a specific task id |
| `--accept-license` | Accept the IBM license agreement and continue |
| `--team-id <id>` | Team ID (only required for API key of type `general`) |
| `--disable-tool-groups <groups>` | Disable tool groups — single value or comma-separated list (e.g. `subagent` or `subagent,mcp`) |
| `-h, --help` | Display help |

### Sending an initial prompt into an interactive session

The `-p`/`--prompt` flag lives at the **top level**, not under `chat`. Pass it before the subcommand:

```bash
bob -p "your prompt here" chat -w /path/to/workspace
```

---

## `bob run [options] [prompt...]`

Execute a single task in headless (non-interactive) mode.

| Flag | Description |
|------|-------------|
| `-f, --format <format>` | Output format: `pretty`, `json`, or `stream-json` (default: `pretty`) |
| `-w, --workspace <path>` | Workspace directory |
| `--mode <mode>` | Mode to use — built-in or custom mode slug (default: `agent`) |
| `--max-cost <number>` | Maximum total cost limit |
| `--max-turns <number>` | Maximum number of turns limit |
| `--log-level <level>` | Log level: `debug`, `info`, `warn`, `error`, `silent` (or `BOB_LOG_LEVEL` env var) |
| `--disable-mcp` | Disable MCP server initialization |
| `--disable-subagents` | Disable subagent tool registration |
| `--trust` | Mark the current folder as trusted |
| `-r, --resume [task-id]` | Open the resume picker, or resume a specific task id |
| `--accept-license` | Accept the IBM license agreement and continue |
| `--team-id <id>` | Team ID (only required for API key of type `general`) |
| `--disable-tool-groups <groups>` | Disable tool groups — single value or comma-separated list |
| `-h, --help` | Display help |

### Example

```bash
bob run "Fix the OSD crash in bluestore" -w /path/to/workspace
```

---

## Common patterns

```bash
# Interactive session, no initial prompt
bob chat -w /path/to/workspace

# Interactive session with an initial prompt
bob -p "your prompt" chat -w /path/to/workspace

# Headless single-task execution
bob run "your prompt" -w /path/to/workspace

# Auto-approve all tools (interactive)
bob chat --auto-approve -w /path/to/workspace
```
