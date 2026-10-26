# Claude love Codex

<img src="docs/images/banner.webp" alt="Two robots working together: the orchestrator hands a plan to the executor, which sends back a compact report" width="100%">

[![tests](https://github.com/fafnirov/claude-love-codex/actions/workflows/tests.yml/badge.svg)](https://github.com/fafnirov/claude-love-codex/actions/workflows/tests.yml)

Claude Code orchestrates. OpenAI Codex CLI executes. You write one task in plain
words, and Claude decides what to do itself, what to delegate, checks the real
diff and tests, and hands back a single report.

The point is not novelty — it is that **the executor's context stays out of
yours**. Codex reads the files, runs the tools and burns its own tokens; Claude
gets a ~500-token JSON report. In a measured run a task cost ~73k input tokens
on the Codex side and ~0.5k in Claude's context.

```bash
~/.claude/scripts/codex-task.sh run --repo . --test "pytest -q" \
  --scope "src/api/*" "rewrite fetch calls in src/api to axios"
```

```json
{
  "task_id": "20261026-013123-10882-8030",
  "status": "success",
  "changed_files": ["src/api/client.py", "tests/test_client.py"],
  "tests": { "status": "passed", "exit_code": 0 },
  "risk_level": "none",
  "branch": "codex/rewrite-fetch-20261026-013123-10882-8030",
  "commit": "22deb4c…",
  "token_usage": { "input_tokens": 73801, "output_tokens": 790 }
}
```

## What it gives you

- **Isolation.** Every task gets its own `task_id`, branch and git worktree. Your
  working copy is never touched.
- **A quality gate based on facts.** Status comes from the exit code, the actual
  `git diff`, the test exit code, risk detection and scope — never from the
  executor's prose.
- **Atomic merges.** The merge is built and tested in a temporary worktree; the
  `--into` ref moves only after the tests pass, with a compare-and-swap. A failing
  post-merge test cannot leave your branch changed.
- **Cross-review.** Codex reviews your diff, or you review its diff, against the
  real code — findings come back with evidence.
- **Limits that hold.** 3 attempts per task, a time budget, 2 concurrent
  executors, run timeouts, duplicate and no-progress detection.
- **Logs and rotation.** Every task keeps its prompt, event log, diff, test log
  and report; `gc` rotates them but never removes unfinished tasks, failures or
  the merge audit.

## Requirements

- [Claude Code](https://docs.anthropic.com/claude-code)
- [OpenAI Codex CLI](https://developers.openai.com/codex/cli/), signed in
  (`codex login`)
- git, Python 3 (`python3` or `python`), bash and GNU `timeout`
  (coreutils; on macOS: `brew install coreutils`)

Verified on Windows 11 + Git Bash with `codex-cli 0.163.0-alpha`. Should work on
macOS and Linux; not verified there yet.

## Install

```bash
git clone https://github.com/fafnirov/claude-love-codex.git
cd claude-love-codex
bash install.sh
~/.claude/scripts/codex-task.sh doctor
```

The installer copies the scripts and a Claude Code skill into `~/.claude`, and
installs the executor rules into `~/.codex/AGENTS.md` **only if that file does
not exist yet**. It never touches `settings.json` or your `CLAUDE.md`.

Then add the permissions from [docs/PERMISSIONS.md](docs/PERMISSIONS.md) so that
routine calls stop asking for confirmation while `merge` and `clean` keep asking.

## Use it from a conversation

With the skill installed you do not call anything by hand — you talk to Claude:

> rewrite the fetch calls in src/api to axios, run the tests

Claude decides whether to delegate. You can steer it: *"use Codex"*, *"do it
yourself"*, *"run two tasks in parallel"*, *"have Codex review my change"*.

## Commands

| Command | What it does |
|---|---|
| `run` | delegate a task (`--test`, `--scope`, `--task-file`, `--base`, `--timeout`, …) |
| `review` | cross-review a task's diff, or any diff via `--repo/--diff` |
| `merge` | verified atomic merge into `--into` |
| `clean` | remove a task worktree (refuses if it holds uncommitted work) |
| `list` / `show` | audit log and full report |
| `stats` | task counts, durations, Codex token totals |
| `recover` | unfinished tasks and orphaned resources |
| `gc` | log rotation (`--days`, `--max-mb`, `--dry-run`) |
| `doctor` | binary, auth, model, paths |

A task contract (`--task-file task.json`) carries `goal`, `allowed_files`,
`forbidden`, `acceptance`, `test_command`, `timeout`, `max_attempts`,
`depends_on`.

## Security — read this

The Codex sandbox does **not** restrict reads. A delegated task can read any file
your account can read, including `.env` files and `~/.codex/auth.json`, and it can
write outside the worktree into directories you can write to.

**Do not use this on machines holding production keys or sensitive data.**

Full threat model, what is protected and what is not:
[docs/SECURITY.md](docs/SECURITY.md).

## Self-check

The suites use a test double instead of the model, so they cost nothing:

```bash
bash tests/run-tests.sh          # detector, limits, merge gates, parallelism
bash tests/run-lifecycle.sh      # interrupts, orphans, recovery, rotation
bash tests/run-merge-atomic.sh   # merge atomicity and ref updates
```

See [docs/VERIFICATION.md](docs/VERIFICATION.md) for what was verified live
against a real Codex.

## Why the name

The orchestrator plans and decides; the executor writes the code and burns its
own context. Neither replaces the other, and the result is better than either
alone.

<img src="docs/images/hug.webp" alt="The two robot mascots hugging, with a heart above them" width="100%">

## Russian documentation

[README.ru.md](README.ru.md)

## License

MIT
