# permish

OS-enforced sandbox for AI agent tool calls.

The agent declares what permissions a command needs — flags like `--write`, `--net`,
`--write-git` — and they compose freely. If the command tries to do more than declared,
the **kernel** denies the syscall and the command exits non-zero. You don't have to audit
what the command actually does — the OS does it for you.

This is the same idea OpenAI's Codex CLI uses internally (Landlock + seccomp on Linux,
Seatbelt on macOS), packaged as a standalone wrapper you can put in front of *any* agent —
Copilot agent mode, Claude Code, Cursor, Cline, your own scripts, whatever.

## What it does

Flags compose freely. Start with no flags (read-only, anywhere) and add what you need:

| Flag            | Effect                                                              |
| --------------- | ------------------------------------------------------------------- |
| *(none)*        | Read anywhere on the filesystem. No writes. No network. (default)  |
| `--read-local`  | Restrict reads to the workspace. Blocks reading `~/.ssh`, other projects, etc. |
| `--write`       | Write to workspace + `/tmp`. `.git` stays read-only.               |
| `--write-git`   | Write to workspace including `.git` (implies `--write`).            |
| `--net`         | Allow network access.                                               |
| `--full`        | No restrictions. Escape hatch.                                      |

Flags combine: `--write --net`, `--write-git --net`, `--read-local --write`, etc.

`/tmp` is always a fresh tmpfs that disappears when the command exits.

## Why you want this

The honest answer to "can I trust this complicated `git` pipeline the agent wants to run?"
is usually "I don't know, and I don't want to read it." `permish` lets you stop reading
the command and start trusting the *declared mode* instead:

- **Agent right** → command does what it claimed → exits 0, you got your answer.
- **Agent wrong** → command tries to write `.git` or hit the network → kernel denies it,
  command exits non-zero, no damage done. You see the failure and intervene.

## Install

### Linux

```bash
sudo apt install bubblewrap            # or: dnf install bubblewrap / pacman -S bubblewrap
sudo install -m 0755 permish /usr/local/bin/permish
```

### macOS

```bash
sudo install -m 0755 permish /usr/local/bin/permish
# sandbox-exec ships with macOS — nothing to install
```

### Windows

Run inside WSL2 with bubblewrap installed. Native Windows is not supported (yet).

## Usage

```bash
permish --              git log --stat master..HEAD  # read anywhere (default)
permish --read-local -- grep -r TODO .               # read only within workspace
permish --write      -- python process.py
permish --write --net   -- pip install requests
permish --write-git  -- git commit -am 'wip'
permish --write-git --net -- git push
permish --full       -- some-command-you-fully-trust  # escape hatch
```

### Options

| Flag                  | Effect                                                               |
| --------------------- | -------------------------------------------------------------------- |
| `--read-local`        | Restrict reads to the workspace (default: read anywhere).            |
| `--write`             | Allow writing to workspace + `/tmp`. `.git` stays read-only.         |
| `--write-git`         | Allow writing to workspace including `.git` (implies `--write`).     |
| `--net`               | Allow network access.                                                |
| `--full`              | No restrictions. Escape hatch.                                       |
| `--workspace PATH`    | Override workspace root (default: cwd). Writes are confined to here. |
| `--read-path PATH`    | Grant extra read-only path. Repeatable.                              |
| `--write-path PATH`   | Grant extra writable path beyond workspace. Repeatable.              |
| `--quiet`             | Suppress the `[permish]` banner that prints to stderr.               |
| `--explain`           | Print the sandbox command that would run, then exit 0.               |

### What "writes" actually means

`permish write` blocks writes everywhere on the filesystem **except**:

- The workspace directory and below (with `.git` carved out as read-only)
- `/tmp` (fresh tmpfs)
- Any extra path you pass with `--write`

So your home directory, `/etc`, system Python's site-packages — all read-only.

### What "no network" actually means

On Linux, the command runs in its own network namespace with no interfaces. `connect()`
fails with `ENETUNREACH`. Localhost binds also fail because there's no `lo` interface.

On macOS, outbound network is denied via Seatbelt. Localhost is allowed by default (because
tons of tooling needs it); if you want truly zero network including loopback, edit the
profile.

## Using it with VS Code Copilot agent

The trick is to make the agent prefix every shell command with `permish [FLAGS] -- ...`,
then use VS Code's terminal auto-approve to whitelist `permish` invocations by flags.

### 1. Tell the agent to use it

Drop `.github/copilot-instructions.md` into your repo (sample in this directory). The agent
will read it and learn to call `permish [FLAGS] -- <command>` instead of bare commands.

### 2. Auto-approve sandboxed commands in `settings.json`

```json
{
  "chat.tools.terminal.autoApprove": {
    "/^permish -- /": true,
    "/^permish --read-local -- /": true,
    "/^permish --write -- /": true
  }
}
```

Any `permish` invocation not matched by a `true` pattern (e.g. `--write-git`, `--net`,
`--full`) will fall through and require explicit approval. The `false` value exists in
this setting but is only useful to override a broader `true` pattern — it's not needed
here since unmatched commands default to requiring approval.

### 3. Comparison: VS Code built-in sandboxing (`chat.agent.sandbox.enabled`)

VS Code 1.99+ has its own OS-level sandboxing for agent terminal commands (macOS and Linux
only). It's worth understanding how it differs from permish.

| | permish | VS Code sandbox |
|---|---|---|
| Per-command permissions | Yes — agent declares flags each time | No — single fixed policy for everything |
| User sees each command | Yes — approval dialog per command | No — all commands auto-approved silently |
| Goal | Informed approval | Zero friction |

permish is about *informed approval*: you still confirm each command, but your confirmation
is load-bearing because the OS enforces the declared scope. You're not auditing `git log`
to decide if it's safe — you're confirming it's running in a read-only sandbox.

VS Code's sandbox trades that per-command visibility for zero friction. If you want
confirmation dialogs to go away entirely and are happy with a single fixed policy, it may be
sufficient on its own. See the
[agent sandboxing docs](https://code.visualstudio.com/docs/copilot/agents/agent-tools#_sandbox-agent-commands)
for configuration options.

Note: VS Code has no "auto-reject" mechanism. Commands not matched by a `true` pattern in
`autoApprove` still show a confirmation dialog — the user sees them and can approve manually.
The `false` value is only useful to override a broader `true` pattern, forcing manual approval
for specific commands even when a catch-all would otherwise auto-approve them.

## Known limitations

1. **Not a security boundary against a determined adversary.** This is defense against
   *mistakes*, not malice. A model that has been prompt-injected and decides to escape
   could still find creative paths — see [Ona's report on Claude Code](https://ona.com/stories/how-claude-code-escapes-its-own-denylist-and-sandbox)
   on how an agent reasoned its way around bubblewrap by using `/proc/self/root`. For
   adversarial threat models, run inside a VM or a hardened container with seccomp + an
   egress proxy.

2. **bubblewrap requires unprivileged user namespaces.** Some Linux distros (Debian-based
   with restrictive AppArmor profiles, hardened kernels) disable these. Test with
   `bwrap --ro-bind / / true` first; if that fails, you'll need to enable
   `kernel.unprivileged_userns_clone=1` or install the AppArmor profile for bwrap.

3. **`--read-local` blocks the user home dir but not the whole filesystem.** It denies
   reading file contents outside the workspace (and a short allowlist of tool configs like
   `~/.gitconfig`), but system paths (`/usr`, `/System`, etc.) remain readable so programs
   can load their own binaries and libraries. If you need a stricter read boundary, extend
   the Seatbelt profile or use a VM.

4. **The agent could call shell built-ins or write to env vars to influence its parent
   process — but it can't, because the wrapped command runs in a separate process. Its
   exit/output is the only thing that escapes.

## License

MIT. Do whatever you want. No warranty.
