# aws-clipboard-login

One-copy AWS login for macOS. Copy the short-term creds from your SSO / console
page; a tiny background daemon detects them, identifies the account via
`sts:GetCallerIdentity`, and registers them as a named AWS profile backed by
`credential_process`. Every `aws` / SDK call after that picks up the new creds
automatically — no `export AWS_…` dance, no re-login when switching accounts.

## How it works

```
[ SSO page ]  →  pbcopy  →  clipboard-monitor  →  aws-from-clipboard
                                                    │
                                                    ├─ sts:GetCallerIdentity  → account_id
                                                    ├─ ~/.aws/session-creds-<profile>.json
                                                    └─ ~/.aws/config [profile <profile>]
                                                           credential_process = aws-cred-process <profile>
```

- **`clipboard-monitor`** — launchd agent. Polls `pbpaste` once per second,
  appends unique entries to `~/.clipboard-history`, and when it sees both
  `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` on the clipboard, runs
  `aws-from-clipboard`. Sends a macOS notification on success/failure.
- **`aws-from-clipboard`** — parses the creds, calls `sts:GetCallerIdentity`,
  looks up the account in `~/.config/aws-clipboard-login/profiles.conf` to get
  the profile name + region, writes `~/.aws/session-creds-<profile>.json`, and
  ensures the `[profile <name>]` block in `~/.aws/config` exists.
- **`aws-cred-process`** — the `credential_process` helper. Reads the JSON
  creds file and prints them with a short `Expiration` so the SDK re-invokes
  it frequently (picking up fresh creds without restarting processes).

## Requirements

- macOS (uses `pbpaste`, `osascript`, `launchd`)
- `aws` CLI on `PATH`
- `python3` (ships with macOS)

## Install

```
git clone https://github.com/BudhirajaMadhav/aws-clipboard-login.git
cd aws-clipboard-login
./install.sh
```

With no flags, `install.sh` prompts you to add account → nickname → region
mappings interactively. Re-run it any time to add more, or pass flags to
skip the prompt:

```
./install.sh \
    --profile 123456789012:dev:us-east-1 \
    --profile 210987654321:prod:eu-west-1
./install.sh --no-prompt    # CI / silent re-install
```

The mappings live in `~/.config/aws-clipboard-login/profiles.conf` — feel
free to edit directly:

```
# ACCOUNT_ID  PROFILE_NAME  REGION
123456789012  dev           us-east-1
```

Accounts not listed still work — they get registered under a profile named
after the account ID, in `AWS_CLIPBOARD_DEFAULT_REGION` (default
`us-east-1`).

## Use

1. Sign in to AWS IAM Identity Center / SSO.
2. Click the "Copy" button for the short-term credentials.
3. Within ~1 s, a macOS notification shows `ACCOUNT_ID → profile`.
4. `export AWS_PROFILE=<profile>` (or set it once in your shell rc) and run
   `aws` commands normally. The last-logged-in profile is also mirrored to
   `default` so bare `aws` calls work too.

## Uninstall

```
./uninstall.sh
```

Removes the launchd agent and the `~/.local/bin` symlinks. Leaves your
`~/.aws/` and `~/.config/aws-clipboard-login/` alone.

## Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `AWS_CLIPBOARD_CONFIG` | `~/.config/aws-clipboard-login/profiles.conf` | Account → profile/region map |
| `AWS_CLIPBOARD_DEFAULT_REGION` | `us-east-1` | Region for unlisted accounts |
| `CLIPBOARD_HISTORY` | `~/.clipboard-history` | Where the monitor stashes recent clipboard entries |

## Files it touches

| Path | Who writes it | Purpose |
|------|--------------|---------|
| `~/.local/bin/{clipboard-monitor,aws-from-clipboard,aws-cred-process}` | `install.sh` (symlinks) | Entry points |
| `~/Library/LaunchAgents/com.user.clipboard-monitor.plist` | `install.sh` | launchd agent definition |
| `~/.config/aws-clipboard-login/profiles.conf` | `install.sh`, you | Account map |
| `~/.clipboard-history` | `clipboard-monitor` | Rolling 50-entry clipboard buffer |
| `~/.aws/config` | `aws-from-clipboard` | Appends `[profile <name>]` blocks |
| `~/.aws/session-creds-<profile>.json` | `aws-from-clipboard` | Creds consumed by `aws-cred-process` |
| `/tmp/clipboard-monitor.log` | `launchd` | stdout/stderr of the monitor |

## Security notes

- Short-term creds land on disk at `~/.aws/session-creds-*.json`. They're
  readable by your user account only (same threat model as `~/.aws/credentials`).
- The monitor reads every clipboard entry. Nothing leaves your machine — it
  only shells out to `aws sts` when creds are detected.
- `aws-from-clipboard` is only triggered when both `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_ACCESS_KEY` appear in a single clipboard write. Randomly copied
  text won't invoke it.

## License

MIT — see [LICENSE](./LICENSE).
