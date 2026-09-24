# bob-shell-setup

Personal tooling for running **IBM Bob Shell** agents against the [Ceph](https://github.com/ceph/ceph) source tree, plus a helper script for tracking open issues on [tracker.ceph.com](https://tracker.ceph.com) and tooling for collecting and evaluating historical git provenance for ceph-mgr classes.

The goal of this repo is to make parallel, AI-assisted development on a large open-source codebase practical from a single laptop. Rather than working on one issue at a time, `launch-bob-agents.sh` spins up multiple Bob Shell agents simultaneously — each isolated in its own git worktree with its own branch — so multiple tracker issues can be researched, implemented, and committed concurrently without conflicts. The companion `ceph-tracker-issues.sh` script keeps that workflow grounded by giving a fast, at-a-glance view of every open issue assigned to you, enriched with the latest activity from both Redmine and GitHub PRs, so you always know what needs attention before dispatching agents. Together with object history collectors and AI assessment guides, these tools compress the feedback loop between "issue is open" and "patch is ready for review."

---

## Repository layout

```
.
├── tracker/                        # Ceph tracker issue reporting tools
│   └── ceph-tracker-issues.sh      # Fetch & render open Ceph tracker issues to HTML
├── gui/                            # GUI frontend & agent orchestrator
│   ├── bob-agents-gui.py           # Tkinter GUI launcher
│   ├── launch-bob-agents.sh        # Launch N parallel Bob/Claude agents in Tilix tabs
│   ├── bob-agents-gui.spec         # PyInstaller build spec
│   ├── logo.png                    # App icon
│   └── logo.gif                    # App icon fallback
├── object-history/                 # Git history extraction & curation tools
│   ├── collect-object-history-v4.sh # Rename-aware git history corpus collector (v4)
│   ├── sync-object-history.sh      # Sync corpus/intent artefacts from remote via rsync
│   ├── get-object-history.sh       # CLI tool to inspect collected history & signals
│   └── collect-object-history-v4-whiteboard-defense.md
├── assessment/                     # Intent dataset ETL & HTML explorer generation
│   ├── build_dataset.py            # Aggregates parsed intents & source code into dataset.json
│   ├── generate_html.py            # Compiles dataset.json into interactive standalone HTML
│   ├── parse_data.py               # Markdown parser & status extractor
│   ├── dataset.json                # Structured function assessment dataset
│   └── parsed_intents.json         # Extracted intent records
├── scripts/                        # Build scripts & helper utilities
│   ├── build-executable.sh         # PyInstaller build script for standalone GUI binaries
│   ├── query_ceph_tracker.py       # Ceph tracker query helper
│   └── query_ceph_tracker.sh       # Ceph tracker bash wrapper
├── Inputs/
│   ├── bob-instructions            # Per-agent task instructions (default prompt file)
│   ├── bob-cli-reference.md        # Quick reference for the Bob Shell CLI
│   ├── claude-cli-reference.md     # Reference for Claude Code CLI
│   ├── history-assessment-guide.md # Guide for AI agents assessing git history into intent artefacts
│   ├── git-history-curator-guide.md# Guide for curator-style history extraction
│   ├── mgr-objects.md              # Inventory of all ceph-mgr C++ classes & tracker status
│   ├── unit-test-prompt-guide.md   # Prompt guide for AI test-writing agents
│   └── Prompts/                    # Per-task prompt suites (history, whiteboard defense, etc.)
├── Outputs/
│   ├── WhiteboardDefense/          # Standalone Whiteboard Defense documents & index.html navigation hub
│   │   └── index.html              # Top-level visual navigation hub for all script defenses
│   ├── Intents/                    # Generated intent artefacts (*-intent.md) for 27 ceph-mgr classes
│   ├── assessment-prompts.txt      # Ready-to-run assessment prompts for all 27 mgr classes
│   └── ceph-mgr-intents-assessment.html # Standalone interactive assessment explorer
├── git-worktree-agents/
│   └── SKILL.md                    # Bob skill: multi-agent git worktree coordination rules
└── ceph-tracker/                   # Output directory for ceph-tracker-issues.sh (git-ignored)
```

---

## Tools

### `ceph-tracker-issues.sh`

Fetches every open issue assigned to you on [tracker.ceph.com](https://tracker.ceph.com) (Redmine) and writes a styled, dark-mode HTML report to `./ceph-tracker/<username>-Open-Issues.html`.

**Features**
- Enriches each issue with the timestamp of the last Redmine journal comment.
- Looks up the linked GitHub PR (via Redmine custom field 21) and fetches its `updated_at` timestamp from the GitHub API.
- Compares all timestamps against the previous run and badges any issue or PR updated since then with a **`***NEW***`** marker.
- Tab filter — **All / New / Stale** — written directly into the HTML output.
- `--open-prs` flag opens every linked PR in a new Chrome window.

#### Prerequisites

| Tool | Purpose |
|------|---------|
| `curl` | API calls to Redmine & GitHub |
| `jq` | JSON processing |
| `google-chrome` / `chromium` | Only needed for `--open-prs` |

#### Authentication

Set **one** of these before running:

```bash
# Preferred — API key (find yours at https://tracker.ceph.com/my/account)
export CEPH_TRACKER_API_KEY="your-redmine-api-key"

# Alternative — username + password
export CEPH_TRACKER_USERNAME="your-username"
export CEPH_TRACKER_PASSWORD="your-password"
```

> **Security note:** Never commit credentials to version control. Use environment variables or a secrets manager. The `.gitignore` excludes the `ceph-tracker/` output directory.

#### Usage

```bash
# Generate the HTML report
./tracker/ceph-tracker-issues.sh

# Generate report AND open all PRs in Chrome
./tracker/ceph-tracker-issues.sh --open-prs
```

Output is written to `./ceph-tracker/<your-username>-Open-Issues.html`.

---

### `launch-bob-agents.sh`

Opens **N Tilix tabs** in a single window on your local machine, each SSH-ing into the remote host and starting a Bob Shell agent in its own git worktree (`ceph-agent-1` … `ceph-agent-N`). The script also automatically synchronises `Inputs/` to the remote host (`~/bob-shell-inputs`) so agents have access to guides and reference docs.

**Why worktrees?** Each agent works on a separate branch without touching the others' working trees. They share the same `.git` object store so commits, history, and objects are shared.

#### Prerequisites

| Requirement | Details |
|---|---|
| [Tilix](https://gnome.github.io/tilix/) | Terminal emulator with multi-tab DBus API |
| SSH access to the remote host | Configured in `~/.ssh/config` (key-based auth recommended) |
| Bob Shell installed on the remote host | `bob` must be on `$PATH` |
| Git worktrees created on the remote | Run the setup step below once |

#### One-time remote setup

Create the worktrees on the remote host (replace paths/branches to match your setup):

```bash
# Run this ON THE REMOTE HOST once
cd /home/szuraski/ceph
for i in $(seq 1 5); do
    git worktree add ../ceph-agent-$i -b agent/$i
done
```

#### Authentication

```bash
# Set your Bob Shell API key before launching
export BOBSHELL_API_KEY="your-bob-api-key"
```

#### Per-agent task instructions

By default, instructions are loaded from [`Inputs/bob-instructions`](Inputs/bob-instructions), or you can provide a custom prompt file using `--instructions <path>`.

Format: one entry per agent, blank line between entries:

```
https://tracker.ceph.com/issues/12345
Fix the OSD crash in the bluestore layer

https://tracker.ceph.com/issues/67890
Investigate slow recovery after node failure
```

- **Line 1** of each entry: tracker URL (passed as context to Bob).
- **Line 2** of each entry: the prompt/instruction for that agent.
- The number of agents launched matches the number of entries in the prompt file (minimum 1).
- Agents with no matching entry open an interactive `bob chat` session.

Agents are assigned in order: entry 1 → agent-1, entry 2 → agent-2, etc.

#### Usage

```bash
chmod +x gui/launch-bob-agents.sh

# Launch with default prompt file (Inputs/bob-instructions) on remote host
./gui/launch-bob-agents.sh

# Launch locally on your workstation without SSH
./gui/launch-bob-agents.sh --local

# Launch in single workspace mode without git worktrees (e.g. for Whiteboard Defense analysis)
./gui/launch-bob-agents.sh --local --no-worktrees --instructions Outputs/Prompts/whiteboard-defense-prompts.md

# Preview agent plan without starting any processes or writing files
./gui/launch-bob-agents.sh --dry-run
./gui/launch-bob-agents.sh --local --no-worktrees --dry-run --instructions Outputs/Prompts/whiteboard-defense-prompts.md

# Launch with custom instructions / prompt file
./gui/launch-bob-agents.sh --instructions Outputs/assessment-prompts.txt
./gui/launch-bob-agents.sh --local --instructions Outputs/assessment-prompts.txt
```

This uploads wrapper scripts to `/tmp/bob-agent-<N>.sh` on the remote host for each agent (avoiding SSH quoting issues), then opens Tilix tabs that SSH in and execute those scripts.

---

### Object History & Assessment Tooling

Scripts for extracting git history provenance and generating intent artefacts for `ceph-mgr` components:

#### `collect-object-history-v4.sh`
Rename-aware corpus collector. Resolves the full path history of `.cc` and `.h` files across renames (e.g., historical renames such as `MgrPyModule.cc` → `ActivePyModule.cc`), collecting non-merge commits, scoped diffs per historical segment, ctags function lists, and blame.

```bash
# Run inside a ceph worktree on remote host
bash object-history/collect-object-history-v4.sh [output_dir]
```

#### `sync-object-history.sh`
Pulls the collected object-history corpus (or generated intent artefacts) from the remote host to your local machine via `rsync`.

```bash
# Sync v3 raw corpus
bash object-history/sync-object-history.sh

# Also sync intent artefacts (*-intent.md)
bash object-history/sync-object-history.sh --intent
```

#### `get-object-history.sh`
Helper CLI to inspect pre-collected git history for a specific class or method locally or remotely over SSH.

```bash
bash object-history/get-object-history.sh ActivePyModules dispatch_remote
bash object-history/get-object-history.sh DaemonServer --signals
bash object-history/get-object-history.sh --list
```

---

### Guides and Reference Materials (`Inputs/`)

- [`Inputs/history-assessment-guide.md`](Inputs/history-assessment-guide.md): Prompting strategy and instructions for AI agents assessing git history to identify `SATISFIES`, `DIVERGED`, `UNGROUNDED`, and `OVERCAUTIOUS` implementation findings.
- [`Inputs/git-history-curator-guide.md`](Inputs/git-history-curator-guide.md): Guide for extracting multi-evidence per-method change histories.
- [`Inputs/mgr-objects.md`](Inputs/mgr-objects.md): Complete reference index of all 28 C++ classes in `src/mgr/`, detailing source files, architectural roles, test coverage status, and tracker tickets.
- [`Inputs/unit-test-prompt-guide.md`](Inputs/unit-test-prompt-guide.md): Prompt guide for AI test-writing agents, including intent artefact consumption.
- [`Inputs/Object History/`](Inputs/Object History/): Example intent artefacts produced from corpus analysis (`ClusterState`, `DaemonServer`, `DaemonState`, `DaemonStateIndex`, `MgrClient`).

---

### `git-worktree-agents/SKILL.md`

A **Bob skill** that governs agent behaviour when running inside one of the git worktrees. Install it into your Bob Shell configuration to have every agent automatically follow the coordination rules.

**What the skill enforces**
- Agents identify their own worktree and branch at startup.
- Agents stay on their own `agent/<N>` branch and never touch another agent's worktree.
- New work branches follow the naming convention `wip-sz-<trackernumber>-<brief-description>`.
- Commit messages follow a consistent format including `Fixes:`, `Signed-off-by:`, and `Assisted-by: IBM Bob`.
- A blocked-action list prevents dangerous operations (sudo, `git push`, writes outside the home directory, etc.) without explicit user approval.
- Completed work is announced in a structured summary format so you can coordinate across tabs.

See [`git-worktree-agents/SKILL.md`](git-worktree-agents/SKILL.md) for the full rule set.

---

## Environment variables summary

| Variable | Used by | Description |
|---|---|---|
| `CEPH_TRACKER_API_KEY` | `ceph-tracker-issues.sh` | Redmine API key (preferred auth) |
| `CEPH_TRACKER_USERNAME` | `ceph-tracker-issues.sh` | Redmine username (fallback auth) |
| `CEPH_TRACKER_PASSWORD` | `ceph-tracker-issues.sh` | Redmine password (fallback auth) |
| `CEPH_TRACKER_OUTPUT_DIR` | `ceph-tracker-issues.sh` | Override output directory (default: `./ceph-tracker`) |
| `BOBSHELL_API_KEY` | `launch-bob-agents.sh` | Bob Shell API key for all agents |

---

## `.gitignore` recommendations

Add the following to keep secrets and generated output out of version control:

```gitignore
# Generated tracker report output
ceph-tracker/*.html
ceph-tracker/.last_run_ts

# Never commit credentials
.env
*.env
```

---

## License

This repository contains personal workflow tooling and is not an IBM product. Use at your own discretion.
