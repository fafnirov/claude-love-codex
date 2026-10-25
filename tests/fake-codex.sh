#!/usr/bin/env bash
# Test double for the Codex binary: exercises the whole delegation pipeline
# without calling a model. Injected through CODEX_BIN. Controlled by env:
#   FAKE_ACTION  ok | nochange | env | secret | sql | rmrf | symlink | binary |
#                rename | hidden | deltest | outside | breaktest | breakmain
#   FAKE_EXIT    exit code (default 0)
#   FAKE_SLEEP   delay in seconds (for timeout tests)
#   FAKE_JSON    good | corrupt | empty
set -u

ACTION="${FAKE_ACTION:-ok}"
EXITC="${FAKE_EXIT:-0}"
SLEEP="${FAKE_SLEEP:-0}"
JSONMODE="${FAKE_JSON:-good}"

DIR=""
OUTFILE=""
prev=""
for a in "$@"; do
  case "$prev" in
    -C|--cd) DIR="$a" ;;
    -o|--output-last-message) OUTFILE="$a" ;;
  esac
  prev="$a"
done
if [ -n "$DIR" ] && command -v cygpath >/dev/null 2>&1; then
  DIR="$(cygpath -u "$DIR" 2>/dev/null || echo "$DIR")"
fi
[ -n "$DIR" ] || DIR="$PWD"

[ "$SLEEP" != "0" ] && sleep "$SLEEP"

cd "$DIR" 2>/dev/null || { echo "fake-codex: no such directory $DIR" >&2; exit 66; }

case "$ACTION" in
  ok)
    printf '\ndef mul(a, b):\n    return a * b\n' >> calc.py
    printf 'from calc import add, mul\n\nassert add(2, 3) == 5\nassert mul(3, 4) == 12\nprint("ok")\n' > test_calc.py
    ;;
  nochange) : ;;
  env)
    printf 'DB_PASSWORD=supersecret123\n' > .env
    ;;
  secret)
    printf 'API_KEY = "sk-abcdefghijklmnopqrstuvwx"\n' >> config.py
    ;;
  sql)
    mkdir -p migrations
    printf 'DROP TABLE users;\n' > migrations/002_drop.sql
    ;;
  rmrf)
    printf '#!/bin/sh\nrm -rf /var/data\n' > cleanup.sh
    ;;
  symlink)
    printf 'import os\nos.symlink("/etc/passwd", "link")\n' >> tool.py
    ;;
  binary)
    printf '\x00\x01\x02\x03binary\x00' > blob.bin
    ;;
  rename)
    git mv calc.py calculator.py 2>/dev/null || mv calc.py calculator.py
    ;;
  hidden)
    # a dangerous edit buried among harmless ones
    printf '# comment\n' >> README.md
    printf 'def helper():\n    return 1\n' >> calc.py
    mkdir -p migrations
    printf 'TRUNCATE TABLE audit_log;\n' > migrations/003_truncate.sql
    printf '# another harmless edit\n' >> README.md
    ;;
  deltest)
    printf 'from calc import add\n\nassert add(1, 1) == 2\n' > test_calc.py
    ;;
  outside)
    printf 'tool\n' > tool.py
    ;;
  breaktest)
    printf '\ndef mul(a, b):\n    return a + b\n' >> calc.py
    printf 'from calc import add, mul\n\nassert add(2, 3) == 5\nassert mul(3, 4) == 12\nprint("ok")\n' > test_calc.py
    ;;
  breakmain)
    # breaks existing code without touching the tests: the regression must be
    # caught by the test run at merge time
    printf 'def add(a, b):\n    return a - b\n' > calc.py
    ;;
esac

case "$JSONMODE" in
  good)
    echo '{"type":"session.created","session_id":"fake-1"}'
    echo '{"type":"item.completed","item":{"type":"agent_message","text":"done (double)"},"usage":{"input_tokens":111,"output_tokens":22}}'
    ;;
  corrupt)
    echo '{"type":"session.created","session_id":"fake-1"}'
    echo 'this is not json'
    echo '{"type":"item.completed","item":{"type":"agent_mess'
    ;;
  empty) : ;;
esac

[ -n "$OUTFILE" ] && [ "$JSONMODE" = "good" ] && printf 'done (double)' > "$OUTFILE"
exit "$EXITC"
