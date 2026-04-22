#!/bin/bash
# Install aws-clipboard-login on macOS:
#   - symlinks bin/ scripts into ~/.local/bin
#   - writes the launchd plist into ~/Library/LaunchAgents and (re)loads it
#   - seeds ~/.config/aws-clipboard-login/profiles.conf
#   - interactively prompts for new account mappings (skip with --no-prompt)
#
# Flags:
#   --profile ACCOUNT_ID:NAME:REGION   Add/replace a mapping (repeatable).
#   --no-prompt                        Skip the interactive "add mapping?" prompt.
#   --help                             Show this message.
#
# Examples:
#   ./install.sh                                          # installs + prompts
#   ./install.sh --profile 123456789012:dev:us-east-1     # non-interactive
#   ./install.sh --no-prompt                              # CI / re-install
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.clipboard-monitor.plist"
PLIST_DEST="$AGENTS_DIR/$PLIST_NAME"
CONFIG_DIR="$HOME/.config/aws-clipboard-login"
CONFIG_FILE="$CONFIG_DIR/profiles.conf"
DEFAULT_REGION="${AWS_CLIPBOARD_DEFAULT_REGION:-us-east-1}"

profile_args=()
prompt=1
while [ $# -gt 0 ]; do
    case "$1" in
        --profile)
            [ -n "${2:-}" ] || { echo "error: --profile needs ACCOUNT_ID:NAME:REGION" >&2; exit 2; }
            profile_args+=("$2")
            prompt=0
            shift 2
            ;;
        --no-prompt)
            prompt=0
            shift
            ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$BIN_DIR" "$AGENTS_DIR" "$HOME/.aws" "$CONFIG_DIR"

for f in clipboard-monitor aws-from-clipboard aws-cred-process; do
    chmod +x "$PROJECT_DIR/bin/$f"
    ln -sfn "$PROJECT_DIR/bin/$f" "$BIN_DIR/$f"
    echo "  linked $BIN_DIR/$f → $PROJECT_DIR/bin/$f"
done

# Seed the config once; never clobber an existing one.
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$PROJECT_DIR/config/profiles.conf.sample" "$CONFIG_FILE"
    echo "  wrote   $CONFIG_FILE"
fi

# Interactive prompt: only if stdin is a TTY and no --profile / --no-prompt was passed.
if [ "$prompt" -eq 1 ] && [ -t 0 ]; then
    existing=$(awk '!/^[[:space:]]*#/ && NF>=2' "$CONFIG_FILE" 2>/dev/null || true)
    echo ""
    if [ -n "$existing" ]; then
        echo "Current account mappings:"
        printf '%s\n' "$existing" | awk '{printf "  %-15s %-20s %s\n", $1, $2, $3}'
        echo ""
    else
        echo "No account mappings configured yet."
        echo ""
    fi
    while true; do
        printf 'Add an account mapping? [y/N]: '
        read -r yn </dev/tty || break
        case "$yn" in
            [yY]|[yY][eE][sS])
                printf '  AWS account ID:     '; read -r acct </dev/tty
                printf '  Nickname:           '; read -r name </dev/tty
                printf "  Region [%s]: " "$DEFAULT_REGION"; read -r region </dev/tty
                [ -z "$region" ] && region="$DEFAULT_REGION"
                if [ -z "$acct" ] || [ -z "$name" ]; then
                    echo "  ✗ skipped — account ID and nickname are required"
                    continue
                fi
                profile_args+=("$acct:$name:$region")
                ;;
            *) break ;;
        esac
    done
    echo ""
fi

# Apply --profile entries (both CLI-passed and interactively collected).
for entry in "${profile_args[@]+"${profile_args[@]}"}"; do
    IFS=':' read -r acct name region <<< "$entry"
    if [ -z "${acct:-}" ] || [ -z "${name:-}" ] || [ -z "${region:-}" ]; then
        echo "error: bad --profile value: $entry (want ACCOUNT_ID:NAME:REGION)" >&2
        exit 2
    fi
    tmp=$(mktemp)
    awk -v a="$acct" '!/^[[:space:]]*#/ && NF>=1 && $1==a {next} {print}' "$CONFIG_FILE" > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
    printf '%s  %s  %s\n' "$acct" "$name" "$region" >> "$CONFIG_FILE"
    echo "  added   $acct → $name ($region)"
done

# Render plist with absolute path (launchd wants a real path, not a symlink target).
sed "s|__BIN_DIR__|$BIN_DIR|g" \
    "$PROJECT_DIR/launchd/$PLIST_NAME" > "$PLIST_DEST"
echo "  wrote   $PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"
echo "  loaded  com.user.clipboard-monitor"

touch "$HOME/.aws/config"
echo ""
echo "✓ Installed. Copy AWS short-term creds from your SSO page to trigger auto-login."
echo "  Config:    $CONFIG_FILE"
echo "  Logs:      /tmp/clipboard-monitor.log"
echo "  Add more:  re-run ./install.sh (prompts), or ./install.sh --profile ACCOUNT:NAME:REGION"
echo "  Uninstall: $PROJECT_DIR/uninstall.sh"
