# bob-shell-setup

Personal tooling for running **IBM Bob Shell** agents against the [Ceph](https://github.com/ceph/ceph) source tree, plus a helper script for tracking open issues on [tracker.ceph.com](https://tracker.ceph.com).

The goal of this repo is to make parallel, AI-assisted development on a large open-source codebase practical from a single laptop. Rather than working on one issue at a time, `launch-bob-agents.sh` spins up five Bob Shell agents simultaneously — each isolated in its own git worktree with its own branch — so multiple tracker issues can be researched, implemented, and committed concurrently without conflicts. The companion `ceph-tracker-issues.sh` script keeps that workflow grounded by giving a fast, at-a-glance view of every open issue assigned to you, enriched with the latest activity from both Redmine and GitHub PRs, so you always know what needs attention before dispatching agents. Together, the tools are meant to compress the feedback loop between "issue is open" and "patch is ready for review."

---

## Repository layout

```
.
├── ceph-tracker-issues.sh      # Fetch & render your open Ceph tracker issues to HTML
├── launch-bob-agents.sh        # Launch 5 parallel Bob Shell agents in Tilix tabs
├── Inputs/
│   ├── bob-instructions        # Per-agent task instructions (one entry per agent)
│   └── bob-cli-reference.md    # Quick reference for the Bob Shell CLI
├── git-worktree-agents/
│   └── SKILL.md                # Bob skill: multi-agent git worktree coordination rules
└── ceph-tracker/               # Output directory for ceph-tracker-issues.sh (git-ignored)
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
./ceph-tracker-issues.sh

# Generate report AND open all PRs in Chrome
./ceph-tracker-issues.sh --open-prs
```

Output is written to `./ceph-tracker/<your-username>-Open-Issues.html`.

---

### `launch-bob-agents.sh`

Opens **5 Tilix tabs** on your local machine, each SSH-ing into a remote host and starting a Bob Shell agent in its own git worktree (`ceph-agent-1` … `ceph-agent-5`).

**Why 5 worktrees?** Each agent works on a separate branch without touching the others' working trees. They share the same `.git` object store so commits, history, and objects are shared.

#### Prerequisites

| Requirement | Details |
|---|---|
| [Tilix](https://gnome.github.io/tilix/) | Terminal emulator with multi-tab DBus API |
| SSH access to the remote host | Configured in `~/.ssh/config` (key-based auth recommended) |
| Bob Shell installed on the remote host | `bob` must be on `$PATH` |
| Git worktrees created on the remote | Run the setup step below once |

#### One-time remote setup

Create the 5 worktrees on the remote host (replace paths/branches to match your setup):

```bash
# Run this ON THE REMOTE HOST once
cd /home/szuraski/ceph
for i in 1 2 3 4 5; do
    git worktree add ../ceph-agent-$i -b agent/$i
done
```

#### Authentication

```bash
# Set your Bob Shell API key before launching
export BOBSHELL_API_KEY="your-bob-api-key"
```

#### Per-agent task instructions (optional)

Edit [`Inputs/bob-instructions`](Inputs/bob-instructions) to pre-load each agent with a task.  
Format: one entry per agent, blank line between entries:

```
https://tracker.ceph.com/issues/12345
Fix the OSD crash in the bluestore layer

https://tracker.ceph.com/issues/67890
Investigate slow recovery after node failure
```

- **Line 1** of each entry: tracker URL (passed as context to Bob).
- **Line 2** of each entry: the prompt/instruction for that agent.
- Agents with no matching entry open an interactive `bob chat` session.

Agents are assigned in order: entry 1 → agent-1, entry 2 → agent-2, etc.

#### Usage

```bash
chmod +x launch-bob-agents.sh
./launch-bob-agents.sh
```

This uploads a small wrapper script to `/tmp/bob-agent-<N>.sh` on the remote host for each agent (avoiding SSH quoting issues), then opens Tilix tabs that SSH in and execute those scripts.

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
