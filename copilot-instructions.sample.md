# Use `permish` for shell commands

Wrap every terminal command with `permish [FLAGS] -- <COMMAND>`.

| Command needs to…                                                    | Flags                         |
| -------------------------------------------------------------------- | ----------------------------- |
| Read inside the workspace only                                       | *(none)*                      |
| Read outside the workspace (other repos, `~/.ssh`)                   | `--read-any`                  |
| Write inside the workspace (not `.git/`)                             | `--write`                     |
| Write inside the workspace + network (e.g. `pip install` in a venv)  | `--write --net`               |
| Modify git state (commit, checkout, stash, rebase)                   | `--write-git`                 |
| Push, pull, fetch, clone                                             | `--write-git --net`           |
| Write outside the workspace (`pip install --user`, `npm -g`)         | `--write-any` (often `--net`) |
| User explicitly asked to bypass the sandbox                          | `--full`                      |

Use `--write` for linters, formatters, type checkers, test runners, build tools, and package manager scripts — these can cache into the workspace even when they look read-only.

`Read-only file system` / `Operation not permitted` / `Network is unreachable` = sandbox denied a syscall. Retry with the next broader flag. Never silently escalate to `--full`.
