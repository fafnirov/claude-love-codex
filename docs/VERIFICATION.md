# Verification

What was actually run, and what was not. No claim here rests on documentation
alone.

## Automated suites

They use a test double in place of the Codex binary, so they cost nothing and are
deterministic.

| Suite | Checks | Result |
|---|---|---|
| `tests/run-tests.sh` | risk detector on real git diffs, scope, executor self-commits, test states, CLI modes, limits, parallelism, merge gates, audit | 96 / 96 |
| `tests/run-lifecycle.sh` | SIGINT, timeout, orphaned lock, orphaned worktree, corrupt report, restart, log rotation, stats | 25 / 25 |
| `tests/run-merge-atomic.sh` | failing post-merge tests, ref targeting, compare-and-swap, branch moved past the gate, HEAD switched mid-check, control cases | 47 / 47 |

Run them with the environment the user has, not a special one:

```bash
env -u PYTHONDONTWRITEBYTECODE bash tests/run-tests.sh
env -u PYTHONDONTWRITEBYTECODE bash tests/run-lifecycle.sh
env -u PYTHONDONTWRITEBYTECODE bash tests/run-merge-atomic.sh
```

## Verified against a live Codex

- **End-to-end project.** A small REST API (stdlib only) built from a plan:
  two independent modules delegated in parallel, a dependent HTTP layer, docs.
  Tests passed; the API was then exercised over real HTTP by the orchestrator
  (201 / 400 / 404 / 204 on the expected routes).
- **Parallel execution.** Two live executors at once on independent modules:
  distinct task ids, independent worktrees and logs, sequential verified merges.
- **Conflict handling.** Two live tasks editing the same file: the conflict was
  detected, the merge refused, `--ack` did not bypass it, the target branch
  stayed unchanged and the second task's work remained on its branch.
- **Cross-review, both directions.** Codex reviewing orchestrator-written code
  found a `ZeroDivisionError` and a `KeyError` and reproduced both by executing
  the code. Reviewing Codex-written code caught a regression that the automated
  gate had passed (a task run without tests had deleted a variable
  initialisation).
- **Risk detection on a live diff.** A task asked to add a migration containing
  `DROP TABLE`: `risk_level: high`, automatic merge refused, merge allowed only
  after explicit `--ack`.
- **Sandbox probes** on synthetic secrets — see [SECURITY.md](SECURITY.md).

## Measured token usage

Across 13 live tasks: 994,021 input and 9,500 output tokens on the Codex side,
476 seconds of execution. Each task returned a compact report of roughly 400–600
tokens into the orchestrator's context.

Input totals include cached tokens. Cost is deliberately not computed: there is
no reliable pricing data in the tooling, and an invented number would be worse
than none.

## Pre-publication review

Before the first release the repository was reviewed by Codex itself, reading the
actual sources. It found fifteen issues; the substantive ones were fixed and
covered by new tests:

- `changed_files` missed work the executor had committed on its own, which could
  hide a change from the scope check and report `no_changes`;
- `merge` merged the branch tip instead of the commit that passed the gate, so a
  commit added after the report could slip in unverified;
- the checked-out branch was read before the tests but used after them, so a
  branch switch during the check could land the merge on the wrong branch;
- scope matching accepted `calc.py.bak` for the pattern `calc.py`;
- the documentation described the recursion guard as a hard guarantee;
- `docs/PERMISSIONS.md` suggested allowing `codex-run.sh`, which bypasses the
  driver's gates entirely;
- `clean` reported success even when git refused to remove the worktree;
- the tamper fingerprint missed `.git/config` in a linked worktree;
- `python` and the installed test layout were not portable.

Known and documented rather than fixed: attempt counters, the time budget and
duplicate detection are not atomic under exactly simultaneous starts.

## Not verified

- macOS and Linux beyond CI: the suites run in GitHub Actions on ubuntu,
  macos and windows, but the live Codex path was exercised only on
  Windows 11 + Git Bash.
- Parallel execution with more than two live executors.
- The `model_unavailable` status (implemented from the observed error text, not
  reproduced on purpose).
- Behaviour on very large repositories and very long tasks.
- Codex permission profiles as a way to restrict reads.
