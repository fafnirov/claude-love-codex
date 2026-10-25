# Threat model

Everything below was verified with live probes on **synthetic** secrets, on
Windows 11 with `[windows] sandbox = "elevated"` in the Codex config and
`codex-cli 0.163.0-alpha`. Numbers and verdicts come from actual runs, not from
documentation.

## What the sandbox actually does

| Operation | Result |
|---|---|
| Read files outside the working directory | **allowed** |
| Read `~/.codex/auth.json` | **allowed** |
| Write into the user's home directory | denied by the sandbox |
| Write into another writable directory (e.g. the system temp dir) | **allowed** |

A worktree isolates the **repository**, not the filesystem.

## Protected

- **Integrity of the target branch.** The merge is built and tested in a
  temporary worktree; the `--into` ref moves only after tests pass, via a
  compare-and-swap against the SHA recorded before the check.
- **The user's uncommitted work.** `merge` refuses to run against a dirty working
  copy when the target branch is checked out; `clean` refuses to remove a
  worktree that holds uncommitted changes.
- **Repository changes.** Every task works on its own branch in its own worktree.
- **The checked-out branch.** When `--into` names another branch, only that ref
  moves; HEAD, the index and the working files are untouched.
- **Recursion (partly).** The driver refuses to start when `CODEX_TASK_ACTIVE`
  is set, and the executor rules forbid calling Claude Code back. This is a
  guard, not a sandbox: a process that unsets the variable can bypass it, and
  nothing stops a `claude` binary from being executed.

## Not protected

- **Reading anything on disk.** The executor can read `.env` files, keys and
  `~/.codex/auth.json`. Nothing in this project prevents or detects that.
- **Writing outside the worktree** into directories the user can write to.
- **Network access** by the executor.
- **File contents reaching the model** as part of a request.
- **Concurrent bookkeeping.** Duplicate detection, attempt counters and the time
  budget are plain files without locking. Two processes starting at the very same
  moment can both pass a check or lose an update. The slot locks (`mkdir`) are
  atomic; these counters are not.

## Residual risk

A delegated task is third-party code running with your account's privileges and
read access to your whole disk. Do not use delegation on machines that hold
production keys or data that must not reach the executor or the model.

## Tamper detector (not secret protection)

Around every run the driver fingerprints a small set of files: `~/.codex/AGENTS.md`,
`~/.claude/settings.json`, `~/.claude/CLAUDE.md`, the integration scripts and the
repository's `.git/config`. If any of them changed during the task, the report
gets `risk_level: high`, status `needs_review`, and automatic merge is refused.

This is a **post-hoc detector**, not prevention: it notices a change after it
happened and knows nothing about reads. It cannot see a secret being read.

`~/.codex/config.toml` and `auth.json` are excluded because they change while
Codex runs and would produce constant false positives. The source of those writes
is not confirmed by any log, so this project makes no claim about it.

## Hardening that is not configured here

Codex ships permission profiles (`codex sandbox -P <profile>`,
`--sandbox-state-readable-root`). They are the supported way to restrict reads.
This project does not configure them and does not modify your Codex config —
doing so safely requires comparative testing on your machine.

## Reporting a problem

Open an issue describing the behaviour and how to reproduce it. Do not include
real secrets, tokens or logs containing them.
