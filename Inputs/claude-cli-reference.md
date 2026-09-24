# Claude Code CLI Reference

Generated from `claude --help`.

---

## Top-level: `claude [options] [command] [prompt]`

Interactive session by default. Use `-p`/`--print` for non-interactive (headless) output.

| Flag | Description |
|------|-------------|
| `prompt` | Positional argument — your prompt text |
| `-p, --print` | Print response and exit (non-interactive/headless mode) |
| `-c, --continue` | Continue the most recent conversation in the current directory |
| `-r, --resume [session-id]` | Resume a conversation by session ID, or open interactive picker |
| `-w, --worktree [name]` | Create a new git worktree for this session |
| `-n, --name <name>` | Display name for the session |
| `--model <model>` | Model alias (`fable`, `opus`, `sonnet`) or full name |
| `--permission-mode <mode>` | `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `plan` |
| `--dangerously-skip-permissions` | Bypass all permission checks (sandboxes only) |
| `--system-prompt <prompt>` | System prompt for the session |
| `--append-system-prompt <prompt>` | Append to the default system prompt |
| `--add-dir <directories...>` | Additional directories to allow tool access to |
| `--allowed-tools <tools...>` | Comma/space-separated list of tool names to allow |
| `--disallowed-tools <tools...>` | Comma/space-separated list of tool names to deny |
| `--tools <tools...>` | Restrict to a specific set of built-in tools; `""` disables all |
| `--mcp-config <configs...>` | Load MCP servers from JSON files or strings |
| `--max-budget-usd <amount>` | Maximum spend on API calls (only with `--print`) |
| `--output-format <format>` | `text` (default), `json`, or `stream-json` (only with `--print`) |
| `--effort <level>` | Effort level: `low`, `medium`, `high`, `xhigh`, `max` |
| `--autocompact <auto\|tokens>` | Auto-compact window size (`auto` or token count) |
| `--bg, --background` | Start in background, return session ID immediately |
| `--bare` | Minimal mode — skips hooks, LSP, plugins, CLAUDE.md auto-discovery |
| `--safe-mode` | Disable all customisations (CLAUDE.md, skills, plugins, hooks, MCP) |
| `--verbose` | Override verbose mode from config |
| `-v, --version` | Output the version number |
| `-h, --help` | Display help |

### Subcommands

| Command | Description |
|---------|-------------|
| `agents` | Manage background agents |
| `attach <id>` | Open a background session in this terminal |
| `auth` | Manage authentication |
| `doctor` | Check the health of the Claude Code installation |
| `install [target]` | Install / update Claude Code (`stable`, `latest`, or version) |
| `logs <id>` | Print a background session's recent terminal output |
| `mcp` | Configure and manage MCP servers |
| `plugin` / `plugins` | Manage Claude Code plugins |
| `rm <id>` | Delete a background session |
| `stop` / `kill <id>` | Stop a background session |
| `update` / `upgrade` | Check for updates and install if available |

---

## Common patterns

```bash
# Interactive session, no initial prompt
claude

# Interactive session with an initial prompt
claude "your prompt here"

# Headless single-task execution (non-interactive, prints and exits)
claude -p "your prompt here"

# Headless with working directory
claude -p "your prompt here" --add-dir /path/to/workspace

# Headless with a specific model
claude -p "your prompt here" --model sonnet

# Auto-approve all edits (interactive)
claude --permission-mode acceptEdits

# Bypass all permissions (sandboxed environments only)
claude --dangerously-skip-permissions "your prompt here"

# Continue the most recent conversation
claude --continue

# Resume a specific session
claude --resume <session-id>

# Run in background and get a session ID
claude --bg "your prompt here"

# Attach to a running background session
claude attach <id>
```

---

## Headless (`-p`) vs interactive

| Scenario | Command |
|----------|---------|
| Run prompt, print result, exit | `claude -p "prompt"` |
| Stream output as JSON | `claude -p "prompt" --output-format stream-json` |
| Limit spend | `claude -p "prompt" --max-budget-usd 0.50` |
| Interactive TUI | `claude` |
| Interactive with initial prompt | `claude "prompt"` |

---

## How the Bob Agent Launcher uses Claude Code

When **AI System → Claude Code** is selected, the launcher calls:

```bash
claude -p "<prompt body>"
```

The prompt body is the content of each `.md` file from the instructions directory,
with the YAML frontmatter (`--- … ---`) stripped before passing to `claude`.
Each agent gets one `.md` file as its prompt.
