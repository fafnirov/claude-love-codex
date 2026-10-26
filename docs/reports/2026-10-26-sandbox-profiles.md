# Comparative study: can the Codex sandbox restrict reads?

Date: 2026-10-26. Host: Windows 11 Pro 10.0.26200, Git Bash, `codex-cli
0.163.0-alpha.10.2`, sandbox backend `elevated`.

**Goal:** find a supported configuration that stops the executor from reading
files outside explicitly allowed directories, while keeping `codex-task.sh`, git
worktrees and the test runs working.

**Answer: no such configuration exists on this host with this build.** Nothing
was changed. The recommendation is to keep the current settings and keep the
documented limitation.

---

## Method

`codex sandbox -- <command>` runs an arbitrary command under the same sandbox
backend the executor uses, **without involving the model**. Every cell below is
an exit code or a file-existence marker from a probe script, not a model's
description of what it could do. Synthetic secrets only; no real credential file
was read or printed.

Probe: `probe.ps1`, 15 checks, run identically in every mode. Written in
PowerShell on purpose — bash does not survive every backend (see below), so a
bash-based probe would have measured the shell, not the sandbox.

## What the CLI actually offers

Taken from `--help` and from error messages, not from documentation:

| Surface | Fact |
|---|---|
| `windows.sandbox` | accepts exactly `elevated`, `unelevated`, `mxc` — *"unknown variant `bogus`, expected one of `elevated`, `unelevated`, `mxc`"* |
| `mxc` | *"failed to prepare MXC sandbox: native MXC is unavailable on this executor"* |
| `sandbox_mode` | `read-only` (default for `codex sandbox`) or `workspace-write` |
| Permission profiles | `[permissions.<name>]` plus `-P <name>` or `default_permissions`; a profile has `sandbox`, `read`, `write`, `network` (`network` expects a `NetworkToml` struct) |
| `--sandbox-state-readable-root`, `--sandbox-state-disable-network` | require `--sandbox-state-json`, an opaque state produced by the `codex/sandbox-state` app-server API — not reachable from the CLI alone |

### Why profiles cannot restrict reads here

Two refusals that contradict each other:

- any profile under the elevated backend →
  *"windows sandbox failed: elevated Windows sandbox requires effective `:root`
  read access"*
- a read-restricting profile under the unelevated backend →
  *"windows sandbox failed: Restricted read-only access requires the elevated
  Windows sandbox backend"*

A profile that explicitly grants `read = [":root"]` fails the same way, so the
elevated backend refuses to start whenever a profile is in play at all. Read
restriction needs a backend that is unavailable (`mxc`), and the backend that
works demands full read access by design.

## Mode matrix

`ro` = `sandbox_mode="read-only"`, `ww` = `sandbox_mode="workspace-write"`.
1 = allowed, 0 = denied.

| Check | no sandbox | elevated ro | elevated ww | unelevated ro | unelevated ww |
|---|---|---|---|---|---|
| 1. read inside the worktree | 1 | 1 | 1 | 1 | 1 |
| 2. write inside the worktree | 1 | 0 | 1 | 0 | 1 |
| 3. **read a secret next to the worktree** | 1 | **1** | **1** | **1** | **1** |
| 4. **read a secret in a user directory** | 1 | **1** | **1** | **1** | **1** |
| 5. write outside the worktree (temp) | 1 | 0 | **1** | 0 | **1** |
| 6a. read `.git/config` | 1 | 1 | 1 | 1 | 1 |
| 6b. `git status` | 1 | 0 | 0 | 1 | 1 |
| 6c. `git diff` | 1 | 0 | 0 | 1 | 1 |
| 6d. `git commit` | 1 | 0 | 0 | 0 | 1 |
| 7a. `git worktree add` | 1 | 0 | 0 | 0 | 0 |
| 7b. `git worktree remove` | 1 | 0 | 0 | 0 | 0 |
| 8a. python | 1 | 1 | 1 | 1 | 1 |
| 8b. bash | 1 | 1 | 1 | **0** | **0** |
| 9. read instruction files | 1 | 1 | 1 | 1 | 1 |
| 10a. DNS resolve | 1 | 1 | 1 | 0 | 0 |
| 10b. TCP connect (443, nothing sent) | 1 | **0** | **0** | **0** | **0** |

Rows 3 and 4 are the goal of this study: **every available mode allows them.**

### Write boundary, measured precisely

Under `elevated` + `workspace-write`:

```
WRITE_OK   C:\Windows\Temp\clc-sbx\outside\w1.txt
WRITE_OK   C:\Windows\Temp\w2.txt
WRITE_DENY C:\Users\<user>\clc-probe-tmp\w3.txt
WRITE_DENY C:\Users\<user>\w4.txt
```

So "workspace-write" is not confined to the workspace: temp directories are
writable, the user profile is protected. This matches the live finding recorded
in `docs/SECURITY.md`.

### Things the matrix shows that the earlier report did not

- **Outbound connections are blocked** in both sandbox backends (TCP to :443
  fails while the baseline succeeds). Only DNS resolution still works under
  `elevated`. Credit where due: the sandbox does restrict the network for
  commands the executor runs.
- `codex doctor` reports *"sandbox: restricted fs + restricted network · backend
  elevated"*. "Restricted fs" refers to writes; reads are not restricted, as
  rows 3–4 show. The label alone should not be read as read isolation.

### Scope note

Rows 6b–7b describe what a command **inside** the sandbox can do. In this
project git, worktrees and merges are executed by `codex-task.sh` itself, which
runs **outside** the sandbox — that is why delegation works today even though
`git status` fails inside it. Switching backends therefore affects what the
*executor* can do during a task, not the driver.

## Minimal recommended profile

**Keep the current configuration.** No change improves read isolation, and the
alternative backend costs real functionality:

| Candidate | Verdict |
|---|---|
| `windows.sandbox = "elevated"` (current) | keep — the only backend where bash works for the executor |
| `windows.sandbox = "unelevated"` | reject — bash cannot start (*"CreateFileMapping … Win32 error 5"*), DNS dies, reads stay open anyway |
| `windows.sandbox = "mxc"` | unavailable on this host |
| `[permissions.*]` profile | refused by the working backend |
| `--sandbox-state-readable-root` | needs the app-server state API |

## Proposed diff for `~/.codex/config.toml`

For the stated goal — **none**. Any read-restricting edit either fails to start
or breaks the executor. For the record, the only edit that would be worth making
*if a future build makes MXC available on this host*:

```diff
 [windows]
-sandbox = "elevated"
+# MXC is the only backend that can restrict reads; verify availability first:
+#   codex sandbox -c 'windows.sandbox="mxc"' -- powershell -NoProfile -Command "echo ok"
+# Expected on success: "ok". Today it prints:
+#   "failed to prepare MXC sandbox: native MXC is unavailable on this executor"
+sandbox = "mxc"
```

Do not apply this until the verification command prints `ok`.

## Application and rollback procedure

Should the MXC check ever succeed:

```bash
# 1. back up
cp ~/.codex/config.toml ~/.codex/config.toml.bak-$(date +%Y%m%d)

# 2. apply the one-line change (manually, or with an editor)

# 3. verify isolation and functionality with the same probe
powershell -NoProfile -ExecutionPolicy Bypass -File probe.ps1          # baseline
codex sandbox -- powershell -NoProfile -ExecutionPolicy Bypass -File probe.ps1

# 4. accept only if rows 3-4 report 0 while rows 1-2, 8a-8b report 1

# 5. roll back
cp ~/.codex/config.toml.bak-YYYYMMDD ~/.codex/config.toml
codex-task.sh doctor   # must report the backend again
```

Rollback is a file copy; nothing else is touched. The driver reads the model and
backend from the Codex config at every run, so no cache needs clearing.

## Risks and functional limits

- **The goal is not met.** The executor can still read any file the account can
  read. Delegation stays unsafe on machines holding production keys — the
  `NOT READY` verdict stands for that use.
- Switching to `unelevated` would silently break tasks whose verification runs
  under bash, and the loss of DNS would break any task that fetches packages.
- `workspace-write` permits writes to temp directories outside the worktree; the
  tamper detector in `codex_meta.py` notices changes to the tracked files only.
- All of this is specific to Windows. On macOS and Linux Codex uses different
  backends (Seatbelt / Landlock + seccomp) that may restrict reads; that was not
  tested here and must not be assumed.

## Artifacts

- Probe script: `C:\Windows\Temp\clc-sbx\probe.ps1` (bench removed after the run)
- Synthetic secrets used: `adjacent-secret.txt`, `clc-probe-tmp\fake-secret.txt`
  — both created for this study and deleted afterwards
- No real credentials were read; `~/.codex/auth.json` was not opened during this
  study
