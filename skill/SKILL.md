---
name: claude-love-codex
description: Delegate bulk implementation work to OpenAI Codex CLI from Claude Code, with git worktree isolation, a fact-based quality gate and atomic merges. Use when a task means large refactors, generating tests, routine migrations, implementing isolated modules, or analysing a lot of source - and when a second opinion (cross-review) on a diff is wanted. Also use when the user says "delegate", "use Codex", or asks to run tasks in parallel.
---

# Claude love Codex

Claude Code is the orchestrator. Codex CLI is the executor. Every delegated task
runs in its own git worktree and branch; the main working copy is never touched.

Entry point: `~/.claude/scripts/codex-task.sh` (override with `CLC_SCRIPTS`).

## When to delegate

Delegate to Codex:

- large refactors across many files;
- implementing isolated modules against a clear contract;
- generating or repairing tests;
- routine code migrations;
- analysing large amounts of source.

Do it yourself:

- planning, architecture, decomposition;
- one- or two-file edits and one-liners;
- diagnosing a bug and choosing the fix;
- reviewing results and deciding what to accept.

Do not delegate when writing the task and checking the result costs more than
making the change. Do not invent subtasks just to run things in parallel.

## Rules

- Never run two executors on overlapping files without coordination.
- Never let Codex call Claude Code back (the driver blocks it; keep it that way).
- Always pass `--test` for code changes: the quality gate rests on tests.
- Stop after 3 attempts at the same task and diagnose instead of iterating.
- Never return raw logs or whole files to the conversation; report the compact
  result and keep the logs local.
- Never add `--ack` or `--force` on your own to get past a refusal.

## Usage

```bash
# delegate with verification and boundaries
~/.claude/scripts/codex-task.sh run --repo . --test "pytest -q" \
  --scope "src/api/*" "rewrite fetch calls in src/api to axios"

# task contract (goal, allowed_files, forbidden, acceptance, test_command, ...)
~/.claude/scripts/codex-task.sh run --repo . --task-file task.json

# cross-review of a task, or of any diff you produced yourself
~/.claude/scripts/codex-task.sh review <task_id> --acceptance "..."
~/.claude/scripts/codex-task.sh review --repo . --diff my.patch

# merge, always verified; add --test when the task had none
~/.claude/scripts/codex-task.sh merge <task_id> --into main --test "pytest -q"
~/.claude/scripts/codex-task.sh clean <task_id>

# housekeeping
~/.claude/scripts/codex-task.sh doctor | list | show <id> | stats | recover | gc
```

## Reading the result

The run prints one compact JSON report: `status`, `changed_files`, `tests`,
`risk_level`, `risks`, `warnings`, `branch`, `commit`, `token_usage`.

Statuses: `success`, `needs_review`, `tests_failed`, `tests_not_run`,
`no_changes`, `no_progress`, `failed`, `timeout`, `model_unavailable`,
`blocked`, `budget_exhausted`, `duplicate`, `parallel_limit`.

The status is computed from facts — Codex's exit code, the actual git diff, the
test exit code, risk detection and scope — never from the executor's own prose.
Check the diff before telling the user the work is done.

## Safety

`merge` refuses on conflicts (even with `--ack`), on a dirty working copy, on
risky changes and on failing or missing required tests. It builds the merge in a
temporary worktree, tests it there, and only then moves the `--into` ref with a
compare-and-swap. `clean` refuses to remove a worktree holding uncommitted work.

The executor can read any file the user can read, including secrets outside the
worktree. Do not delegate on machines holding production keys.
