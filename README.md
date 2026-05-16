# permish

OS-enforced sandbox for AI agent tool calls.

The agent declares what permissions a command needs — flags like `--write`, `--net`, `--write-git` — and they compose freely. If the command tries to do more than declared, the **kernel** denies the syscall and the command exits non-zero. You don't have to audit what the command actually does — the OS does it for you.

This is the same idea OpenAI's Codex CLI uses internally (Landlock + seccomp on Linux, Seatbelt on macOS), packaged as a standalone wrapper you can put in front of *any* agent — Copilot agent mode, Claude Code, Cursor, Cline, or your own scripts.

## What it does

Flags compose freely. Start with no flags (read-only, workspace only) and add what you need:

| Flag            | Effect                                                              |
| --------------- | ------------------------------------------------------------------- |
| *(none)*        | Read only within the workspace. No writes. No network. (default)   |
| `--read-any`    | Allow reading the whole filesystem (other repos, `~/.ssh`, `/etc`, etc.). |
| `--write`       | Write to workspace + a fresh per-invocation `$TMPDIR`. `.git` stays read-only. |
| `--write-git`   | Write to workspace including `.git` (implies `--write`).            |
| `--write-any`   | Write anywhere on the filesystem (implies `--read-any`).            |
| `--net`         | Allow network access.                                               |
| `--full`        | No restrictions. Escape hatch.                                      |

Flags combine: `--read-any --write`, `--write --net`, `--write-git --net`, `--write-any --net`, etc.

`/tmp` is always a fresh tmpfs that disappears when the command exits.

## Why you want this

The honest answer to "can I trust this complicated `git` pipeline the agent wants to run?" is usually "I don't know, and I don't want to read it." `permish` lets you stop reading the command and start trusting the *declared mode* instead:

- **Agent right** → command does what it claimed → exits 0, you got your answer.
- **Agent wrong** → command tries to write `.git` or hit the network → kernel denies it, command exits non-zero, no damage done. You see the failure and intervene.

## Install

### Linux

```bash
sudo apt install bubblewrap
sudo install -m 0755 permish /usr/local/bin/permish
```

### macOS

```bash
sudo install -m 0755 permish /usr/local/bin/permish
```

## Usage

```bash
permish                   -- grep -r TODO .               # read only within workspace (default)
permish --read-any        -- git log --stat master..HEAD  # need to read outside the workspace
permish --write           -- python process.py
permish --write --net     -- pip install requests         # in a venv inside the workspace
permish --write-any --net -- pip install --user requests  # touches ~/.local
permish --write-git       -- git commit -am 'wip'
permish --write-git --net -- git push
permish --full            -- some-command-you-fully-trust
```

### Options

| Flag                  | Effect                                                               |
| --------------------- | -------------------------------------------------------------------- |
| `--read-any`          | Allow reading the whole filesystem (default: workspace only).        |
| `--write`             | Allow writing to workspace + a fresh per-invocation `$TMPDIR`. `.git` stays read-only. |
| `--write-git`         | Allow writing to workspace including `.git` (implies `--write`).     |
| `--write-any`         | Allow writing anywhere on the filesystem (implies `--read-any`).     |
| `--net`               | Allow network access.                                                |
| `--full`              | No restrictions.                                                     |
| `--workspace PATH`    | Override workspace root (default: cwd). Writes are confined to here. |
| `--read-path PATH`    | Grant extra read-only path. Repeatable.                              |
| `--write-path PATH`   | Grant extra writable path beyond workspace. Repeatable.              |
| `--quiet`             | Suppress the `[permish]` banner that prints to stderr.               |
| `--explain`           | Print the sandbox command that would run, then exit 0.               |

### What "reads" actually means

By default, `permish` blocks reads of file contents in the sensitive parts of the filesystem: every user's home dir (`/Users/*` on macOS, `/home/*` on Linux), mounted drives (`/Volumes`), and root's data. The workspace itself is re-allowed, along with a short tool-config allowlist (`~/.gitconfig`, `~/.config/`) so things like `git` work out of the box. System paths (`/usr`, `/etc`, `/System`, `/Library`) stay readable so programs can operate normally.

Everything else under those blocked trees — `~/.ssh`, other projects under your home dir, mounted disks, another user's files — is unreadable until you pass `--read-any`. Use `--read-path PATH` to grant access to one specific extra location instead of opening up the whole filesystem.

### What "writes" actually means

`permish --write` blocks writes everywhere on the filesystem **except**:

- The workspace directory and below (with `.git` carved out as read-only)
- A fresh per-invocation temp directory on macOS (see `$TMPDIR` handling below) or a fresh `tmpfs` at `/tmp` on Linux.
- Any extra path you pass with `--write-path`

So your home directory, `/etc`, system Python's site-packages — all read-only. Use `--write-any` if the command needs to write outside the workspace (e.g. `pip install --user`, `npm install -g`, writing to `~/.cache`); `.git` is still protected unless you also pass `--write-git`.

### `$TMPDIR` handling

`permish` uses an isolated temp directory and points `$TMPDIR` at it. The standard temp APIs (Python `tempfile`, Go `os.TempDir`, Rust `env::temp_dir`, `NSTemporaryDirectory`, libc `mkstemp` with `-t`, Node `os.tmpdir`) pick it up transparently.

Tools that hardcode `/tmp/...` paths and ignore `$TMPDIR` will see `Operation not permitted` on macOS. Pass `--write-path /tmp` if you need to support this.

### What "no network" actually means

On Linux, the command runs in its own network namespace with no interfaces. `connect()` fails with `ENETUNREACH`. Localhost binds also fail because there's no `lo` interface.

On macOS, outbound network is denied via Seatbelt. Localhost is allowed by default (because tons of tooling needs it); if you want truly zero network including loopback, edit the profile.

## Using it with VS Code Copilot agent

Make the agent prefix every shell command with `permish [FLAGS] -- ...`, then use VS Code's terminal auto-approve to whitelist `permish` invocations by flags.

### 1. Tell the agent to use it

Drop `.github/copilot-instructions.md` into your repo (sample in this directory). The agent will read it and learn to call `permish [FLAGS] -- <command>` instead of bare commands.

### 2. Auto-approve sandboxed commands in `settings.json`

```json
{
  "chat.tools.terminal.autoApprove": {
    "/^permish -- /": true,
    "/^permish --read-any -- /": true,
    "/^permish --write -- /": true
  }
}
```

Any `permish` invocation not matched by a `true` pattern (e.g. `--write-git`, `--write-any`, `--net`, `--full`) will fall through and require explicit approval.

### 3. Comparison: VS Code built-in sandboxing (`chat.agent.sandbox.enabled`)

VS Code 1.99+ has its own OS-level sandboxing for agent terminal commands (macOS and Linux only). It's worth understanding how it differs from permish.

| | permish | VS Code sandbox |
|---|---|---|
| Per-command permissions | Yes — agent declares flags each time | No — single fixed policy for everything |
| User sees each command | Yes — approval dialog per command | No — all commands auto-approved silently |
| Goal | Informed approval | Zero friction |

permish is about *informed approval*: you still confirm each command, but your confirmation is load-bearing because the OS enforces the declared scope. You're not auditing `git log` to decide if it's safe — you're confirming it's running in a read-only sandbox.

VS Code's sandbox trades that per-command visibility for zero friction. If you want confirmation dialogs to go away entirely and are happy with a single fixed policy, it may be sufficient on its own. See the [agent sandboxing docs](https://code.visualstudio.com/docs/copilot/agents/agent-tools#_sandbox-agent-commands) for configuration options.

Note: VS Code has no "auto-reject" mechanism. Commands not matched by a `true` pattern in `autoApprove` still show a confirmation dialog — the user sees them and can approve manually. The `false` value is only useful to override a broader `true` pattern, forcing manual approval for specific commands even when a catch-all would otherwise auto-approve them.

## Known limitations

1. **The sandbox is only as tight as the flags you approved.** If you auto-approve `--write-any --net` (or `--full`), you've effectively turned the sandbox off for those commands. permish's value comes from keeping the permissive flags out of your auto-approve list so they still require an explicit human decision. It also only sandboxes the wrapped command — not the agent process itself, not other tools the agent calls outside `permish`. For threat models that include kernel-level escapes (occasional CVEs in unprivileged user namespaces), run the whole agent inside a VM or hardened container.

2. **bubblewrap requires unprivileged user namespaces.** Some Linux distros (Debian-based with restrictive AppArmor profiles, hardened kernels) disable these. Test with `bwrap --ro-bind / / true` first; if that fails, you'll need to enable `kernel.unprivileged_userns_clone=1` or install the AppArmor profile for bwrap.

3. **The default mode is a deny-*list*, not deny-default.** It blocks the obviously sensitive trees (`/Users/*`, `/home/*`, `/Volumes`, root's data) and re-allows the workspace, but system paths like `/usr`, `/etc`, `/System`, `/Library` remain readable so programs can load their libraries. On macOS, file *metadata* (existence, size) is readable anywhere so directory traversal doesn't break. If you need a true read boundary against a curious agent, use a VM.

4. **The sandboxed command cannot influence its parent process.** It runs as a separate process, so it cannot set environment variables, change the working directory, or otherwise affect the shell or agent that invoked it. Only its exit code and output escape the sandbox.
