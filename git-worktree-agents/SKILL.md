---
name: git-worktree-agents
description: Use when working on the same git repository with multiple Bob Shell agents in parallel — guides coordination via git worktrees so each agent has its own branch and working directory without conflicts.
---

# Git Worktree Multi-Agent Coordination

This skill governs how Bob Shell operates when running inside a git worktree that is one of several
parallel agents all working on the same repository. Follow these rules for every session.

## Context

Each Bob Shell instance is launched into a dedicated git worktree:

```
/home/szuraski/ceph/              ← main worktree (trunk / main branch)
/home/szuraski/ceph-agent-1/      ← agent 1 worktree (branch: agent/1)
/home/szuraski/ceph-agent-2/      ← agent 2 worktree (branch: agent/2)
/home/szuraski/ceph-agent-3/      ← agent 3 worktree (branch: agent/3)
/home/szuraski/ceph-agent-4/      ← agent 4 worktree (branch: agent/4)
/home/szuraski/ceph-agent-5/      ← agent 5 worktree (branch: agent/5)
```

Every worktree shares the same `.git` object store — commits, objects, and history are shared, but
the working tree and `HEAD` are independent.

## Autonomous operation

Agents running this skill are expected to operate autonomously — proceed without asking for
confirmation unless an action falls into the **blocked list** below.

### Auto-approve (proceed without asking)
All actions not in the blocked list are pre-approved, including but not limited to:
- Reading any file
- Writing or editing files inside `~/szuraski/` (i.e. any path under `/home/szuraski/`)
- Running builds, tests, linters, formatters, and other dev tooling
- All `git` operations **except** those in the blocked list below
- Creating, editing, or deleting branches locally
- Running scripts already present in the repository

### Blocked — always stop and ask the user first
Never execute any of the following without explicit user approval for that specific action:

| Category | Examples |
|---|---|
| `sudo` / privilege escalation | `sudo`, `su`, `doas`, running anything as root |
| Software installation / removal | `apt`, `dnf`, `pip install`, `npm install -g`, `brew`, `make install`, `rpm`, `snap`, `flatpak`, `cargo install`, `go install`, `pip install --user`, `gem install` |
| Process termination | `pkill`, `killall`, `kill -9` (or any `kill` targeting a PID you did not spawn) |
| `git push` | `git push` in any form, including `--force` and `--force-with-lease` |
| Destructive git operations | `git reset --hard`, `git clean -fd`, `git rebase -i` or `git commit --amend` on already-pushed commits, `git stash drop`, `git stash clear` |
| Writes outside `~/szuraski/` | Any file write, delete, or move where the resolved path is not under `/home/szuraski/` |
| Destructive filesystem operations | `rm -rf` on directories, `shred`, `truncate`, `dd` writing to block devices, `chmod`/`chown` on paths outside the worktree |
| System / environment changes | Edits to `/etc/*`, `~/.bashrc`, `~/.profile`, shell startup files; `LD_PRELOAD` or persistent `PATH` manipulation; `sysctl`, `ulimit -H`, `crontab`, `systemctl start/stop/enable` |
| Network transmission to external hosts | `curl`/`wget` with POST/PUT to non-localhost URLs, `scp`, `rsync` to remote hosts, `ssh` to remote hosts, `nc` (netcat) to external addresses |
| Container / VM operations | `docker run`, `podman run` (especially with volume mounts), `vagrant up` |
| Secrets / credential access | Reading from `~/.ssh/`, `~/.gnupg/`, `~/.aws/`, `~/.kube/config`, any `.env` or credential file; piping `env`/`printenv` output externally |

When a blocked action is needed, explain what you intended to do and why, then wait for explicit
approval before proceeding. Do not attempt a workaround that achieves the same effect via a
different command.

## Rules for every session

### 1. Identify yourself at startup
At the start of every conversation, determine which worktree you are in:
```bash
git worktree list
pwd
git branch --show-current
```
State your worktree path and branch clearly so the user knows which agent they are talking to.

### 2. Stay on your branch
Never switch branches inside your worktree. Your branch is `agent/<N>` where `<N>` is your worktree
number. If you need to work on a different branch, tell the user and ask them to rebase or merge
instead.

### 2a. Branch naming convention
When creating a new branch for a piece of work, always use this format:
```
wip-sz-<trackernumber>-<brief-description>
```
Examples:
```
wip-sz-12345-fix-upload-retry
wip-sz-98701-refactor-auth-middleware
```
- `wip-sz` is the constant prefix identifying work-in-progress by Steven Zuraski.
- `<trackernumber>` is the issue/tracker ID (e.g. Jira, GitHub issue, internal tracker).
- `<brief-description>` is a short, hyphen-separated description of the work.

**At the start of every task, check whether a `wip-sz-*` branch already exists for the work:**
```bash
git branch --list "wip-sz-*"
```
- If a matching branch exists, check it out:
  ```bash
  git checkout wip-sz-<trackernumber>-<brief-description>
  ```
- If no branch exists yet, create one from the correct base (usually `main` or `master`) and push it immediately:
  ```bash
  git fetch origin
  git checkout -b wip-sz-<trackernumber>-<brief-description> origin/main
  git push -u origin wip-sz-<trackernumber>-<brief-description>
  ```

If the tracker number or description is not yet known, ask the user before creating the branch.

### 3. Commit often and with clear messages
Make small, logically self-contained commits. Each commit message must follow this exact format:

```
<module>: <Title / brief description>

<Problem description>. <Solution explained>.

Fixes: <tracker URL or ID>
Signed-off-by: stzuraski898 <steven.zuraski@ibm.com>
Assisted-by: IBM Bob
```

Example:
```
uploader: Add retry logic on transient network errors

The uploader failed permanently on transient 503 responses, causing
data loss during network blips. Added exponential back-off retry with
a configurable maximum attempt count.

Fixes: https://tracker.ceph.com/issues/12345
Signed-off-by: stzuraski898 <steven.zuraski@ibm.com>
Assisted-by: IBM Bob
```

Stage only what belongs to the current logical unit of work:
```bash
git add -p          # review and stage hunks selectively
git commit          # opens editor pre-populated with the format above
```

### 4. Pull before starting new work
Before starting any significant new work, fetch and rebase from the main branch:
```bash
git fetch origin
git rebase origin/main    # or origin/master — check with: git remote show origin
```
Resolve any conflicts locally. Do not force-push shared branches.

### 5. Never touch another agent's worktree
Do not read from or write to `/home/szuraski/ceph-agent-<M>/` where `<M>` is not your own number.
Share work through git (branches, commits, cherry-picks) — not the filesystem.

### 6. Sharing work between agents
To share a commit from agent-1's branch into agent-2's branch, the **user** should run:
```bash
# In the agent-2 worktree
git cherry-pick <commit-sha>
```
or open a merge/rebase via the main branch. Bob agents do not cross-invoke each other.

### 7. Announcing completed work
When a meaningful unit of work is done, print a summary in this format so the user can easily
coordinate across tabs:
```
✅ [agent-<N>] <branch>  —  <one-line summary of what was done>
   Commits: <sha1>, <sha2>
   Ready to merge: yes / no (reason if not)
```

### 8. Conflict discipline
If `git status` shows merge conflicts:
1. List the conflicting files.
2. Resolve each one — prefer your changes only when logically correct; otherwise show the user both
   sides and ask.
3. Run tests before committing the resolution.
4. Never use `git checkout --theirs` or `--ours` without explaining why.
