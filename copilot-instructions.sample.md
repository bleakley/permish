# Use `permish` for shell commands

Wrap every terminal command with `permish [FLAGS] -- <COMMAND>`. The kernel enforces the declared flags; if you under-declare, the command fails and you retry with broader flags.

## Flag selection

Start with no flags and add only what's needed:

| Command needs to…                                   | Flags                 |
| --------------------------------------------------- | --------------------- |
| Read inside the workspace only                      | *(none)*              |
| Read outside the workspace (other repos, `/etc`, `~`) | `--read-any`          |
| Write inside the workspace (not `.git/`), no network | `--write`             |
| Write inside the workspace + network (e.g. `pip install` in a venv) | `--write --net`       |
| Modify git state (commit, checkout, stash, rebase)  | `--write-git`         |
| Push, pull, fetch, clone                            | `--write-git --net`   |
| Write outside the workspace (`pip install --user`, `npm -g`, `~/.cache`) | `--write-any` (often `--net`) |
| User explicitly asked to bypass the sandbox         | `--full`              |

The mode applies to the whole wrapped command including pipes and subshells — wrap the outer command, not each piece.

## When it fails

`Read-only file system`, `Operation not permitted`, and `Network is unreachable` mean the sandbox denied a syscall. Don't rewrite the command — re-run with broader flags.

## Don't

- Don't wrap built-in tool calls (file edits, reads) — only shell/terminal commands.
- Don't silently escalate to `--full` to make an error go away. Try narrower flags first; if you genuinely need `--full`, say why.
