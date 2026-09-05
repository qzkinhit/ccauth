# ccauth

Switch between multiple Claude Code accounts with one command, without running `/login` every time.

[中文文档](README.zh-CN.md)

```console
$ ccauth list
  work         alice@example.com          saved 2026-09-05T20:08:53+08:00
* personal     bob@example.com            saved 2026-09-05T20:06:46+08:00

$ ccauth work
(stashed the live credentials back into personal)
Switched to account work -> alice@example.com
  Access token valid for another 7.8 h
```

## Why

Claude Code holds one set of credentials at a time. Logging in as a second account overwrites the first, so people with a work account and a personal account end up re-running `/login` and re-authorising in the browser several times a day.

The credentials themselves are just two pieces of state. `ccauth` saves both as a named profile and writes them back on demand. Everything else stays shared: settings, skills, agents, MCP servers, memory, session history.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/qzkinhit/ccauth/main/install.sh | sh
```

Or by hand:

```sh
curl -fsSL https://raw.githubusercontent.com/qzkinhit/ccauth/main/ccauth -o ~/.local/bin/ccauth
chmod +x ~/.local/bin/ccauth
```

Requirements are Python 3.8 or newer and Claude Code itself. Nothing else is pulled in. If `~/.local/bin` is not on your `PATH`, add it:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## First run

Save the account you are logged in as right now.

```sh
ccauth save work
```

Log in as the other account.

```sh
claude
# inside claude:
/login
# finish the browser authorisation, then quit claude
```

Save that one too.

```sh
ccauth save personal
```

Both accounts are now stored. From here on, switching takes one command.

## Usage

```
ccauth save <name> [--force]   save the currently logged-in account
ccauth use <name>              switch to that account (short form: ccauth <name>)
ccauth list                    list saved accounts, * marks the current one
ccauth status                  show the current account
ccauth rm <name>               delete a saved account
ccauth path                    show where credentials and profiles live
ccauth version                 print the version
```

Bare `ccauth` is the same as `ccauth status`. A bare name is the same as `ccauth use <name>`, so `ccauth work` switches to `work`.

**Restart `claude` after switching.** A running session keeps the account it started with, and may write the old identity back into the config file when it exits. `ccauth` prints a warning when it sees `claude` still running.

## How it works

Claude Code keeps the account in two places.

| | macOS | Linux |
|---|---|---|
| Credentials | login Keychain, generic password `Claude Code-credentials` | `~/.claude/.credentials.json` |
| Identity | `oauthAccount` in `~/.claude.json` | same |

The credential blob is a small JSON object.

```json
{"claudeAiOauth": {"accessToken": "...", "refreshToken": "...",
  "expiresAt": 1788637711000, "refreshTokenExpiresAt": 1820145511000,
  "scopes": ["user:inference", "user:profile"],
  "subscriptionType": "pro", "rateLimitTier": "default_claude_ai"}}
```

`ccauth save` copies both halves into `~/.ccauth/<name>.json`. `ccauth use` writes them back and then deletes the config keys that cache the previous account's subscription and model entitlements, so the next start of `claude` refetches them for the right account.

Three details worth knowing.

1. **Profiles are refreshed on the way out.** The access token rotates roughly every 8 hours. Before switching away, `ccauth` writes the live credentials back into the profile they belong to, so a profile you have not touched for weeks still has a usable refresh token. Refresh tokens are valid far longer than access tokens, so an old profile normally renews itself rather than forcing a new login.
2. **Tokens never reach `argv`.** On macOS the Keychain write goes through `security -i` on stdin, so the token is not visible to `ps`.
3. **The config file is backed up before every write**, to `~/.ccauth/claude.json.bak`.

`ccauth` also reproduces the CLI's own service-name derivation, which appends the first 8 hex digits of `sha256(CLAUDE_CONFIG_DIR)` when that variable is set. So it keeps working inside an isolated config directory, see below.

## Running two accounts at the same time

`ccauth` switches the account globally, which is what most people want. If you need two accounts live in two terminals at once, Claude Code supports that directly through `CLAUDE_CONFIG_DIR`:

```sh
CLAUDE_CONFIG_DIR=~/.claude-work claude
```

That directory gets its own credentials and its own Keychain entry. The cost is that settings, skills, agents, MCP servers and session history are separate too. You can share the parts you care about with symlinks:

```sh
mkdir -p ~/.claude-work
for f in settings.json skills agents commands output-styles CLAUDE.md; do
  ln -sfn ~/.claude/"$f" ~/.claude-work/"$f"
done
```

`ccauth` works inside such a directory as well. Run it with the same `CLAUDE_CONFIG_DIR` set and it will target that directory's credential store.

## Files

| Path | Contents |
|---|---|
| `~/.ccauth/<name>.json` | one saved account, mode `600` |
| `~/.ccauth/claude.json.bak` | backup of the global config from the last write |
| `~/.local/bin/ccauth` | the script |

Override the profile directory with `CCAUTH_HOME`. Force the output language with `CCAUTH_LANG=en` or `CCAUTH_LANG=zh`; without it, the locale decides.

## Security

Profiles hold live OAuth tokens. They are stored with mode `600` in a `700` directory, which is the same protection your SSH private keys get, but they are on disk rather than in the Keychain. That is the tradeoff that makes non-interactive switching possible.

The macOS Keychain item is written with `security add-generic-password -A`, meaning any application running as you can read it without a prompt. This matches how Claude Code itself stores the item, so it does not lower the bar that was already there.

Do not put `~/.ccauth` in a synced folder, a backup that leaves the machine, or a git repository. If a profile leaks, revoke the session from [claude.ai](https://claude.ai/settings) and log in again.

## Troubleshooting

**`No credentials found`** — you are not logged in. Start `claude`, run `/login`, then try again.

**`Keychain write did not verify`** — the login keychain is locked. Unlock it in Keychain Access, or run `security unlock-keychain`.

**Switched, but `claude` still shows the old account** — a `claude` process was running and wrote the old identity back. Quit every session, run `ccauth use <name>` again, then start `claude`.

**`claude` asks you to log in after a switch** — that profile's refresh token expired, which happens after long disuse. Run `/login` for that account and `ccauth save <name> --force` to replace the stored pair.

## Compatibility

Developed against Claude Code 2.1.259 on macOS 15. The Linux path is implemented from the same code paths in the CLI but has had less testing; reports are welcome.

`ccauth` reads and writes files that Claude Code owns. Those formats are not a public interface and may change in a future release. The script fails loudly rather than silently corrupting state, and every config write is backed up first.

## Licence

MIT
