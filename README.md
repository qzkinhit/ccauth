# ccauth

Switch between multiple Claude Code accounts with one command, without running `/login` every time. It also manages Gemini CLI accounts, third-party relays for Antigravity, model routing for Codex and daily check-in on relay sites, and ships a macOS app.

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
  "expiresAt": 1788637711000, "refreshTokenExpiresAt": 1791229711000,
  "scopes": ["user:inference", "user:profile"],
  "subscriptionType": "pro", "rateLimitTier": "default_claude_ai"}}
```

`ccauth save` copies both halves into `~/.ccauth/<name>.json`. `ccauth use` writes them back and then deletes the config keys that cache the previous account's subscription and model entitlements, so the next start of `claude` refetches them for the right account.

Three details worth knowing.

1. **Profiles are refreshed on the way out.** The access token rotates roughly every 8 hours. Before switching away, `ccauth` writes the live credentials back into the profile they belong to, so a profile you have not touched for weeks still has a usable refresh token. The refresh token lasts about 30 days, so a profile you switch to within a month renews itself instead of forcing a new login.
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

## Gemini CLI

`ccauth` also supports switching Google accounts for [Gemini CLI](https://github.com/google-gemini/gemini-cli) using the `gemini` subcommand (all Claude Code commands above remain unchanged):

```sh
ccauth gemini save work            # save current Gemini account
# switch account inside gemini (/auth), then:
ccauth gemini save personal

ccauth gemini work                 # switch back to work
ccauth gemini list                 # list saved Gemini accounts
ccauth gemini status               # show current Gemini account
ccauth gemini rm personal          # delete a saved Gemini profile
ccauth gemini path                 # show Gemini credential & profile paths
```

Gemini profiles are stored separately in `~/.ccauth/gemini/<name>.json` (mode `600`), so profile names like `work` and `personal` do not conflict with your Claude Code profiles. Both `~/.gemini/oauth_creds.json` + `~/.gemini/google_accounts.json` and the macOS Keychain entry (`gemini-cli-oauth` / `main-account`) are handled automatically, with outgoing credentials restashed before switching.

If you prefer a shorter command, you can symlink `gauth` to `ccauth`:

```sh
ln -s ~/.local/bin/ccauth ~/.local/bin/gauth
gauth work
```

## Antigravity

`ccauth agy` switches Antigravity (the `agy` CLI and the desktop app) between the Google sign-in and a third-party Gemini-compatible relay.

```sh
ccauth agy save work                             # save the signed-in Google account as work
ccauth agy accounts                              # list saved Google accounts
ccauth agy use official work                     # back to the Google sign-in, as the work account
ccauth agy models                                # re-read the relays' model lists (also every 15 minutes)
ccauth agy add relay --url https://relay.example.com --key sk-xxxx
ccauth agy use relay                             # switch to the relay
ccauth agy use official                          # switch back to the Google sign-in
ccauth agy list                                  # * marks the active mode
ccauth agy status
ccauth agy rm relay
```

`add` reads the relay's `/v1/models` and records every model whose id starts with `gemini`. Relays often expose one fixed thinking level per model (for example `gemini-4-argon-high`). The local bridge maps the id Antigravity asks for (for example `gemini-4-argon-low`) to the available model of the same family. `--models a,b` sets the list by hand and `--default` sets the fallback model.

Restart `agy` and the desktop app after switching. In terminals that are already open, run `exec $SHELL` first.

### What third-party mode changes

| Part | Change |
|---|---|
| `agy` | `modelProvider: "gemini"` is written to its settings and the shell function `agy` passes the bridge address, so `agy` runs in API-key mode without the Google sign-in |
| Desktop app | The app has no API-key mode. `launchctl setenv CLOUD_CODE_URL` points its backend at the local bridge |
| Local bridge | A LaunchAgent on `127.0.0.1:18765`. Generation requests go to the relay. Account calls (model list, quota and so on) are answered from a local cache |
| installation_id | Each relay gets its own. The official ids are restored on switching back |
| Google session | Left in place. The keychain entry is backed up on the first switch and restored on switching back if it is missing |

The relay receives the conversation, the generation settings and its own key. The Google OAuth token, the project id and the installation id are not sent to the relay, and generation requests are not sent to Google. An account call that is not in the local cache yet is forwarded to Google once and then served from the cache.

In third-party mode the app's model list is rewritten. Carbon is unlocked when the relay serves it, quota shows as full, and Claude and GPT models, which the relay does not serve, are hidden.

### Saving requests on a per-call relay

Each tool call of the agent (reading a file, running a command) sends the result back to the model in a new request, so one question usually costs several requests. Two switches help when the relay bills per call.

```sh
ccauth agy cheap relay gemini-4-hydrogen-xhigh   # tool-result steps use a cheaper model
ccauth agy hint relay on                         # append a request-saving note to the system prompt
ccauth agy cheap relay off                       # turn off
ccauth agy hint relay off
```

With `cheap` on, the bridge looks at the newest message. When it is your question the chosen model answers, and when it is a tool result the cheaper model answers. The first call of every question, which plans the work, stays on the strong model and the execution steps run on the cheaper one. A question that starts with `@h` uses the cheaper model for every call, which suits simple tasks, and `@m` keeps the chosen model for every call. `ccauth agy writing relay on` keeps questions with writing keywords (polish, rewrite, paper, .tex and so on) on the chosen model throughout. It is off by default.

With `hint` on, the bridge asks the model to put independent tool calls into one turn, to read known paths directly, to finish research before writing the text in one step and to answer once it has enough information. A custom text can be passed as the third argument instead of `on`.

`ccauth agy writer relay gemini-4-argon-high` adds a writer model. The bridge tells the model in the system prompt that when its next step is writing (documents, reports, slide text, speaker notes or a long written answer) it should begin the message with `【写作】`, keep the marker while writing and drop it when done. When the previous model message carries the marker, the bridge sends the step to the writer model, and other tool steps stay on the cheap model. The main model states the writing steps in its plan on the first call. A missed marker leaves the step on the cheap model and costs no extra request.

Antigravity wraps only what the user typed in `<USER_REQUEST>`. Messages the app inserts itself, such as a finished background command, lack the tag and are treated as tool steps rather than new questions.

The history carries thought signatures from both models. If the relay rejects a request over a signature, the bridge replaces the signatures with the skip value documented for Gemini and retries once. countTokens requests are estimated locally and not sent to the relay.

### Several keys with automatic fallback

```sh
ccauth agy fallback relay relay2     # use relay2 when relay's key runs out or expires
ccauth agy fallback relay2 relay     # and the other way round
ccauth agy fallback relay off        # turn off
```

When the relay rejects a request because the key's quota or balance is used up, or the key has expired or is invalid, the bridge resends the same request with the fallback key and marks the used-up key until local midnight. While marked, requests start with the fallback key, so no request is spent on the used-up one. The mark clears at midnight, which suits relays that refill quota daily. An upstream pool outage (errors mentioning cooling down or no available channel) does not trigger a switch, since another key on the same relay fails the same way. Manual switching stays `ccauth agy use <name>`. `ccauth agy status` (at the end) and `ccauth agy quota` list the remaining and used balance behind each key through the relay's token-usage endpoint, which costs no model request.

### Daily check-in

NewAPI relays (v1.0, short-lived access token plus a 30-day refresh cookie) that offer a daily check-in can be checked in automatically.

```sh
ccauth agy login relay USERNAME       # log in to the account behind a key, prompts for the password
ccauth agy checkin                    # check in every logged-in account now, skipping ones already done
ccauth agy checkin --install          # check in daily at 00:10, 12:10 and at login
ccauth agy checkin --uninstall        # stop the schedule
```

The refresh cookie is exchanged for a short-lived token on each run. It expires 30 days after login, and the saved password is then used to log in again. Password and cookie live in `~/.ccauth/agy/providers/<name>.json` with mode 600. Running several times a day checks in once, accounts already done today send no request, and accounts on the same site are spaced 30 to 60 seconds apart. Results go to `~/.ccauth/agy/checkin.log`, and `ccauth agy status` shows whether each account checked in today and what it received. Relays that require a captcha for check-in cannot be automated this way.

Some classic NewAPI sites have no check-in button and grant the bonus on the first login of the day. Add them with `ccauth agy site <name> <url> <username> <user_id> [access_token]`. A run first reads the quota log with the access token and skips the site if today's bonus is already there, otherwise logs in once with the password and reads the log again to report the amount. Accounts created through a third-party login need a password set on the site first.

Third-party mode is implemented for macOS only.

## Codex: Gemini main agent, CC Switch subagents

Codex sends the main agent and its subagents to one provider per session, and role files cannot change the provider. `ccauth codex` runs a local router that splits by model name: requests for `gemini-*` go to the Gemini relay saved with `ccauth agy add`, every other model goes to the upstream CC Switch last wrote into `~/.codex/config.toml`, with the request's own Authorization header.

```sh
ccauth codex on                       # turn on, backing up ~/.codex/config.toml first
ccauth codex subagent gpt-6.1-sol     # subagent model, default gpt-6.1-sol
ccauth codex subagent follow          # subagents follow the model CC Switch picked
ccauth codex effort max               # subagent reasoning effort, default max; off leaves it to Codex
ccauth codex main gemini-4-neon-xhigh # main agent model
ccauth codex status
ccauth codex log -f                   # live request log: models, route, result, time, tokens
ccauth codex off                      # restore what CC Switch wrote
```

When on, the provider's `base_url` points at the router, `model` becomes the main model and `[agents]` gets `default_subagent_model` and `default_subagent_reasoning_effort`. The spawning agent can name its own effort and override that setting, so the router also sets `reasoning.effort` to the configured value on requests Codex marks as spawned subagents (`x-openai-subagent: collab_spawn`). A model you pick in Codex itself and the background model `gpt-6-luna` carry no such mark and keep their effort. If the provider refuses that effort, the request is sent again one level lower and the lower level is kept for 30 minutes. A LaunchAgent watches the file and, each time CC Switch rewrites it, records the new upstream and model and applies the edit again. A model you pick in Codex, which Codex writes into the same file, is left as it is and routed by name, so a non-Gemini pick goes to the CC Switch provider.

Some relays answer a system prompt that introduces itself as Codex with 429. In requests sent to the Gemini relay, Codex and OpenAI in developer and system messages and in instructions are replaced with neutral wording. A cooling or withdrawn main model falls back to `gemini-4-hydrogen-xhigh`, then `gemini-3.8-flash-high`, and a used-up relay key follows the `ccauth agy fallback` setting. Changes apply to new Codex sessions.

## macOS app

`mac/` holds a native SwiftUI app covering every ccauth feature: Antigravity official and relay modes, relay settings and balances, Codex routing, daily check-in, and Claude and Gemini CLI accounts. Each action runs the `ccauth` command and the window is drawn from the JSON that `ccauth state` prints, so the app and the command line stay in step.

```sh
cd mac
./build.sh            # builds mac/build/ccauth.app (Apple silicon and Intel)
./build.sh --install  # also copies it to /Applications
```

Building needs the Xcode Command Line Tools (`xcode-select --install`); the app needs macOS 14 or later. It uses `~/.local/bin/ccauth` when present and the copy bundled inside the app otherwise.

## Windows

The Windows package holds `ccauth-gui.exe` (window app) and `ccauth.exe` (command line), built with PyInstaller on GitHub Actions and smoke-tested on Windows before each release. On Windows you get Claude and Gemini CLI accounts, relay management and balances, and daily check-in (Task Scheduler at 00:10 and 12:10). Antigravity third-party mode and Codex routing are macOS only.

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

**`claude` asks you to log in after a switch** — that profile's refresh token expired, which happens after roughly a month without using that account. Run `/login` for that account and `ccauth save <name> --force` to replace the stored pair.

## Compatibility

Developed against Claude Code 2.1.259 on macOS 15. The Linux path is implemented from the same code paths in the CLI but has had less testing; reports are welcome.

`ccauth` reads and writes files that Claude Code owns. Those formats are not a public interface and may change in a future release. The script fails loudly rather than silently corrupting state, and every config write is backed up first.

## Licence

MIT
