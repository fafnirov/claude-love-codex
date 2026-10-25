# Claude Code permissions

Least privilege: routine calls run without asking, anything that changes a branch
or removes a worktree asks every time.

| Command | Mode | Why |
|---|---|---|
| `run` | allow | writes only inside the task worktree |
| `list`, `show`, `stats`, `doctor`, `recover` | allow | read-only |
| `merge` | ask | changes a branch |
| `clean` | ask | removes a worktree |
| `gc` | ask | rotates logs |

Never add a blanket `Bash(*)`.

Add this to the `permissions` object in `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/scripts/codex-run.sh:*)",
      "Bash(~/.claude/scripts/codex-task.sh run:*)",
      "Bash(~/.claude/scripts/codex-task.sh list:*)",
      "Bash(~/.claude/scripts/codex-task.sh show:*)",
      "Bash(~/.claude/scripts/codex-task.sh stats:*)",
      "Bash(~/.claude/scripts/codex-task.sh recover:*)",
      "Bash(~/.claude/scripts/codex-task.sh doctor:*)"
    ],
    "ask": [
      "Bash(~/.claude/scripts/codex-task.sh merge:*)",
      "Bash(~/.claude/scripts/codex-task.sh clean:*)",
      "Bash(~/.claude/scripts/codex-task.sh gc:*)"
    ]
  }
}
```

Permission patterns match the command string as written, so if Claude calls the
script by absolute path, add that spelling too — for example
`"Bash(/home/you/.claude/scripts/codex-task.sh run:*)"` or, on Windows with Git
Bash, `"Bash(/c/Users/you/.claude/scripts/codex-task.sh run:*)"`.

You can also edit permissions with `/permissions` in an interactive `claude`
terminal. The installer does not touch `settings.json` on purpose — Claude Code
protects it from self-modification, and that protection is worth keeping.

Check afterwards: `codex-task.sh doctor` should run without a prompt, and
`codex-task.sh merge <id>` should ask.
