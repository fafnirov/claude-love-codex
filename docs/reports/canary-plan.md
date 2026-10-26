# Canary plan: first realistic run of the integration

Status: **prepared, not executed.** The canary must not run on the working
host. It runs only inside a prepared VM, and only after the preflight below
passes and the operator confirms.

Purpose: exercise the delegation cycle on a project closer to real work than
`calc.py`, in an environment where the executor's unrestricted read access does
not matter.

## What a throwaway repository does and does not limit

A temporary repository limits **what the task is about**. It does not limit what
the executor can read: on Windows no available sandbox mode restricts reads (see
`2026-10-26-sandbox-profiles.md`). While a task runs, everything the account can
read is reachable — other projects, configuration, credentials elsewhere on the
disk.

So the containment in this plan comes from **the environment**, not from the
test repository. Run the canary where there is nothing worth reading.

## Target environment

- **Preferably a separate virtual machine.**
- Shared folders, shared clipboard and drive passthrough **disabled**.
- A **separate `codex login` inside that environment** — not the operator's
  session, so a leaked token is not the main account's token.
- Repository **without a remote**: `git init` only, no `origin`, no push.
- **Synthetic data only.** No `.env`, no tokens, no keys, no user data. Every
  value is invented for the test.
- Global configs (`~/.codex/config.toml`, `~/.claude/settings.json`,
  `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`) are not modified.
- Task logs go to a dedicated `CODEX_TASKS_DIR`, separate from earlier history.

### Two conditions before the first live call

1. **Install the published version inside the VM and get 96/25/47 there.** The
   operator's local `~/.claude/scripts` is older than the repository: it is
   missing the refusal when the task branch moved past the verified commit and
   the refusal when the checked-out branch changed mid-check. Measured on
   2026-10-26: `codex-task.sh` 634 local lines vs 678 published. The canary must
   exercise the published code, not an older copy.

2. **"Separate Codex login" means a separate account.** If the VM signs in with
   the same account as the host, say so plainly in the report: file isolation is
   present, credential and account isolation are not — a token leaked inside the
   VM is still the operator's token, and usage is billed to the same account.
   Either outcome is acceptable for the canary; silently implying the stronger
   one is not.

```bash
BENCH=/c/Windows/Temp/clc-canary          # short path: Win32 limits
export CODEX_TASKS_DIR="$BENCH/tasks"
```

## Run options

### A. Virtual machine — recommended

Isolation boundary: the hypervisor. The executor does not see the host
filesystem at all. Network remains available (the model API needs it), so this
bounds file access, not exfiltration.

Preflight checklist, run **inside** the VM before the canary:

```powershell
# 1. the host profile must be unreachable, not merely protected
Test-Path 'C:\Users\kapranov'            # expect: False (no such path in the VM)
Get-PSDrive -PSProvider FileSystem       # expect: only the VM's own disks
Get-ChildItem \\tsclient\ -ErrorAction SilentlyContinue   # expect: nothing

# 2. shared clipboard off: on the host copy the marker
#    CLC_HOST_CLIPBOARD_PROBE_20261026, then here
((Get-Clipboard) -join '') -match 'CLC_HOST_CLIPBOARD_PROBE_20261026'   # expect: False
#    never print the clipboard itself - compare against the marker only

# 3. this environment has its own Codex identity
Test-Path "$env:USERPROFILE\.codex\auth.json"   # existence only, never opened

# 4. the bench repository has no remote
git -C $BENCH/loans remote -v            # expect: empty
```

Also confirm in the VM settings that folder sharing and drag-and-drop are off —
a checkbox is more reliable evidence than an empty directory listing.

### B. Separate Windows user — acceptable, weaker

Isolation boundary: NTFS permissions between profiles. The other profile is
closed, but **shared locations stay readable**: `C:\ProgramData`, drive roots,
repositories kept outside user profiles, `C:\Windows\Temp`. Use this only if
nothing sensitive lives in those places.

Preflight checklist, run **as the canary user**:

```powershell
# 1. the main profile must be denied, not just empty.
# Never print what these files contain: test readability, not content.
Get-ChildItem 'C:\Users\<main-user>' -ErrorAction SilentlyContinue   # expect: access denied
foreach ($p in @('C:\Users\<main-user>\.codex\auth.json',
                 'C:\Users\<main-user>\.claude\settings.json')) {
  try { $null = Get-Content $p -TotalCount 1 -ErrorAction Stop; "READABLE  $p  <- not isolated" }
  catch { "denied    $p" }
}

# 2. inventory what IS readable from here, and confirm it holds no secrets
Get-ChildItem C:\ProgramData, C:\ -Force -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty FullName -First 40        # names only, never contents
Get-ChildItem D:\, E:\ -ErrorAction SilentlyContinue           # other drives, if any

# 3. separate Codex identity for this account
codex login status                        # expect: logged in; do not paste the raw output

# 4. network: the executor can reach the LAN from here
Test-NetConnection -ComputerName <your-nas-or-server> -Port 445   # decide if that is acceptable

# 5. the toolchain works under this account
bash -c 'echo ok'; python -V; git --version
bash tests/run-tests.sh                   # expect 96/96
```

If step 2 turns up a repository or a config with real credentials in a shared
location, option B is not suitable — move to option A.

## Before the canary: run the existing suites, not live tasks

Interruption and recovery, orphaned locks and worktrees, corrupt reports,
attempt limits, duplicate refusal, budget exhaustion, log rotation and stats are
already covered deterministically by the local suites. Re-running them with live
tasks would cost tokens and prove nothing new.

```bash
git clone https://github.com/fafnirov/claude-love-codex.git     # inside the VM
cd claude-love-codex && bash install.sh
env -u PYTHONDONTWRITEBYTECODE bash tests/run-tests.sh          # expect 96/96
env -u PYTHONDONTWRITEBYTECODE bash tests/run-lifecycle.sh      # expect 25/25
env -u PYTHONDONTWRITEBYTECODE bash tests/run-merge-atomic.sh   # expect 47/47
~/.claude/scripts/codex-task.sh doctor                          # binary, auth, model
```

`canary-preflight.ps1` next to this plan runs the environment checks and these
suites in one pass and prints a report meant to be pasted back for review.

Record the guard fingerprint of the protected files here, and compare it again
at the end.

## Test project: a library loans service

Four coupled modules, stdlib only, fully synthetic — a regression in one module
is visible through another.

```
loans/
  app/__init__.py
  app/models.py      Book, Loan dataclasses; to_dict helpers
  app/rules.py       can_borrow(), due_date(), late_fee()      <- holds the seeded bug
  app/storage.py     LoanStore: add/get/list/return_loan, in-memory, Lock
  app/report.py      overdue(), totals()  -- depends on rules + storage
  tests/test_models.py
  tests/test_rules.py        passes, but does NOT cover the seeded bug
  tests/test_storage.py
  run_tests.py       runs every tests/*.py, exit 1 on the first failure
  README.md
```

Synthetic data only: books `Book A`…`Book D`, borrowers `user1`…`user3`, dates
fixed to 2026-01-01..2026-02-01.

### The seeded regression

`rules.late_fee(days_late)` has an off-by-one: it charges for `days_late - 1`
days. `tests/test_rules.py` checks only `days_late = 0` and a large value where
rounding hides the difference, so **the suite is green with the bug in place**.
`report.totals()` sums those fees, so the error is real and reachable.

This is the honest test of the gate: automated tests say "fine", and only a
reviewer reading the code can catch it.

## Live stages — four Codex calls

| # | Stage | Call | Pass criteria |
|---|---|---|---|
| 1 | Two tasks in parallel | `run --task-file t-report.json` and `run --task-file t-cli.json` together | distinct task ids, independent worktrees, both `success`, scope respected, neither touches `rules.py` |
| 2 | Cross-review hunting the seeded bug | `review <task-report> --focus "late_fee arithmetic"` | the off-by-one is named with evidence from the code — or the miss is recorded honestly, which is also a result |
| 3 | Successful atomic merge | `merge <task-report> --into main --test "python run_tests.py"` | `merged:`, post-merge tests pass, HEAD moves exactly to the verified commit, working copy clean |
| 4 | Merge refused on a regression | task that fixes `late_fee` but breaks `storage`; `merge --test "python run_tests.py"` | merge **refused** with `rejected_tests_failed`, main unchanged, task branch and worktree kept |

Stage 3 costs no model call; stage 4's task does. Four live Codex invocations in
total: two tasks, one review, one regression task.

Between stages the orchestrator reads the actual diff rather than the executor's
summary, and writes its own verdict — that is the second half of cross-review
and costs nothing.

## Task contracts

Written before the run, so the brief is fixed and auditable:

- `t-report.json` — implement `app/report.py` (`overdue`, `totals`) and
  `tests/test_report.py`; allowed files limited to those two; forbidden: touching
  `rules.py` and `storage.py`; acceptance: the repo suite passes.
- `t-cli.json` — implement a stdlib CLI (`python -m app.cli list|overdue`) and
  its test; allowed files limited to `app/cli.py` and `tests/test_cli.py`; same
  prohibitions.
- `t-fix.json` — fix `late_fee` while keeping every existing test green, and
  change `storage` as well. Used in stage 4 to prove the merge gate refuses.

## What gets recorded

- `docs/reports/<date>-canary.md`: the stage table with actual results, exact
  commands, token usage from `stats`, and every deviation from this plan.
- Raw logs stay in `$CODEX_TASKS_DIR/<task_id>/` (prompt, events.jsonl,
  diff.patch, tests.log, tests-after-merge.log, review.json, merge.log).
- The guard fingerprint is compared against the preflight value; any change to a
  protected file is reported, not ignored.

## Budget and stop rules

- **Four live Codex calls.** Based on measured runs (73k–92k input tokens per
  call) that is roughly **300k–400k input tokens** and under 3k output on the
  Codex side, plus 2–5 minutes of executor time. Cost is not estimated — there
  is no reliable pricing data in the tooling.
- Stop immediately and report if: a protected file changes, the executor writes
  outside its worktree, a merge lands without passing tests, or any task touches
  a path outside the bench.
- After the run the bench is deleted; task logs are kept until the report is
  written, then rotated with `gc`.

## Not covered by this canary

- Read isolation — unavailable on Windows. The environment, not the plan,
  provides containment.
- Large repositories, long-running suites, non-Windows hosts.
- Scenarios already proven by the local suites, listed above.
