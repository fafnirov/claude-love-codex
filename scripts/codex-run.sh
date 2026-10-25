#!/usr/bin/env bash
# Thin wrapper around `codex exec`.
#
# Claude love Codex — Claude Code orchestrates, Codex CLI executes.
# Only the executor's final message reaches Claude's context; files, logs and
# reasoning stay local.
#
# Usage:
#   codex-run.sh [--read|--write|--worktree] [--dir DIR] [--out FILE] [extra flags] "task"
#   cat task.txt | codex-run.sh --read -
#
# Modes:
#   --worktree  (default) -s workspace-write --worktree: Codex manages its own worktree
#   --write     -s workspace-write: writes in the given directory
#   --read      -s read-only: analysis and review only
#
# Environment: CODEX_BIN, CODEX_MODE, CODEX_DIR, CODEX_MODEL
set -euo pipefail

MODE="${CODEX_MODE:-worktree}"
DIR="${CODEX_DIR:-$PWD}"
OUT=""
PASS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --read|--write|--worktree) MODE="${1#--}"; shift ;;
    --dir)  DIR="$2"; shift 2 ;;
    --out)  OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# The Codex binary lives in a build-hash directory that changes on update,
# so pick the newest one unless CODEX_BIN says otherwise.
BIN="${CODEX_BIN:-}"
if [ -z "$BIN" ]; then
  if command -v codex >/dev/null 2>&1; then
    BIN="$(command -v codex)"
  else
    LA="${LOCALAPPDATA:-${USERPROFILE:-$HOME}/AppData/Local}"
    command -v cygpath >/dev/null 2>&1 && LA="$(cygpath -u "$LA")"
    BIN="$(ls -1dt "$LA"/OpenAI/Codex/bin/*/codex.exe 2>/dev/null | head -1 || true)"
  fi
fi
if [ -z "$BIN" ]; then
  echo "codex-run: Codex binary not found. Set CODEX_BIN to its path." >&2
  exit 127
fi
if [ ! -f "$BIN" ]; then
  echo "codex-run: the given binary does not exist: $BIN" >&2
  exit 127
fi

case "$MODE" in
  read)     PASS+=(-s read-only) ;;
  write)    PASS+=(-s workspace-write) ;;
  worktree) PASS+=(-s workspace-write --worktree) ;;
  *) echo "codex-run: mode must be read | write | worktree (got: $MODE)" >&2; exit 2 ;;
esac

# On Windows the Codex binary is native and does not understand MSYS paths.
command -v cygpath >/dev/null 2>&1 && DIR="$(cygpath -w "$DIR")"
PASS+=(-C "$DIR")
# Pass the model only when it was set explicitly; otherwise Codex uses its own config.
if [ -n "${CODEX_MODEL:-}" ]; then PASS+=(-m "$CODEX_MODEL"); fi
if [ -n "$OUT" ]; then PASS+=(-o "$OUT"); fi

# Without this redirect Codex waits for a prompt on stdin when it is not
# started from a terminal.
if [ "${1:-}" = "-" ]; then
  exec "$BIN" exec "${PASS[@]}" "$@"
else
  exec "$BIN" exec "${PASS[@]}" "$@" < /dev/null
fi
