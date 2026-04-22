#!/bin/bash
# Install aws-clipboard-login on macOS:
#   - symlinks bin/ scripts into ~/.local/bin
#   - writes the launchd plist into ~/Library/LaunchAgents and (re)loads it
#   - seeds ~/.config/aws-clipboard-login/profiles.conf
#   - interactively helps you add account mappings (paste creds -> detect
#     account -> pick nickname/region); skip with --no-prompt
#
# Flags:
#   --profile ACCOUNT_ID:NAME:REGION   Add/replace a mapping (repeatable).
#   --no-prompt                        Skip the interactive loop.
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

AWS_REGIONS=(
    "us-east-1      N. Virginia"
    "us-east-2      Ohio"
    "us-west-1      N. California"
    "us-west-2      Oregon"
    "eu-west-1      Ireland"
    "eu-west-2      London"
    "eu-central-1   Frankfurt"
    "eu-north-1     Stockholm"
    "ap-south-1     Mumbai"
    "ap-southeast-1 Singapore"
    "ap-southeast-2 Sydney"
    "ap-northeast-1 Tokyo"
    "ap-northeast-2 Seoul"
    "ca-central-1   Canada Central"
    "sa-east-1      São Paulo"
)

has_creds() {
    printf '%s' "$1" | grep -q "AWS_ACCESS_KEY_ID" && \
    printf '%s' "$1" | grep -q "AWS_SECRET_ACCESS_KEY"
}

extract() {  # field_name blob -> value
    printf '%s' "$2" | grep "$1" | head -1 | sed "s/.*$1=//" | tr -d '"'
}

detect_account() {  # ak sk st -> account_id (stdout) or empty
    AWS_ACCESS_KEY_ID="$1" AWS_SECRET_ACCESS_KEY="$2" AWS_SESSION_TOKEN="$3" \
        aws sts get-caller-identity --query Account --output text 2>/dev/null
}

show_regions() {
    echo "  Regions:"
    local i
    for i in "${!AWS_REGIONS[@]}"; do
        printf '    %2d) %s\n' $((i+1)) "${AWS_REGIONS[$i]}"
    done
    echo "    (or type any region name)"
}

resolve_region() {  # choice default -> region
    local choice="$1" default="$2"
    if [ -z "$choice" ]; then
        echo "$default"
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$((choice-1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#AWS_REGIONS[@]}" ]; then
            echo "${AWS_REGIONS[$idx]%% *}"
        else
            echo "$default"
        fi
    else
        echo "$choice"
    fi
}

add_mapping() {  # appends one entry to profile_args or returns 1
    local creds="" clip
    clip=$(pbpaste 2>/dev/null || true)
    if has_creds "$clip"; then
        printf '  AWS creds detected on your clipboard — use them? [Y/n]: '
        local yn
        read -r yn </dev/tty
        case "$yn" in
            ""|[yY]*) creds="$clip" ;;
        esac
    fi
    if [ -z "$creds" ]; then
        echo "  Paste AWS short-term creds (blank line to finish):"
        local line
        while IFS= read -r line </dev/tty; do
            [ -z "$line" ] && break
            creds+="${line}"$'\n'
        done
    fi

    local ak sk st
    ak=$(extract AWS_ACCESS_KEY_ID "$creds")
    sk=$(extract AWS_SECRET_ACCESS_KEY "$creds")
    st=$(extract AWS_SESSION_TOKEN "$creds")
    if [ -z "$ak" ] || [ -z "$sk" ]; then
        echo "  ✗ Couldn't find AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY — skipped"
        return 1
    fi

    local acct
    acct=$(detect_account "$ak" "$sk" "$st")
    if [ -z "$acct" ]; then
        echo "  ✗ sts:GetCallerIdentity rejected those creds (invalid or expired) — skipped"
        return 1
    fi
    echo "  ✓ Account: $acct"

    local existing_name existing_region
    existing_name=$(awk -v a="$acct" '!/^[[:space:]]*#/ && NF>=2 && $1==a {print $2; exit}' "$CONFIG_FILE" 2>/dev/null || true)
    existing_region=$(awk -v a="$acct" '!/^[[:space:]]*#/ && NF>=3 && $1==a {print $3; exit}' "$CONFIG_FILE" 2>/dev/null || true)

    local default_name="${existing_name:-$acct}"
    printf '  Nickname [%s]: ' "$default_name"
    local name
    read -r name </dev/tty
    [ -z "$name" ] && name="$default_name"

    local default_region="${existing_region:-$DEFAULT_REGION}"
    show_regions
    printf '  Region [%s]: ' "$default_region"
    local choice
    read -r choice </dev/tty
    local region
    region=$(resolve_region "$choice" "$default_region")

    profile_args+=("$acct:$name:$region")
    echo "  ✓ Added: $acct → $name ($region)"
}

# --- arg parsing ---------------------------------------------------

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
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# --- install --------------------------------------------------------

mkdir -p "$BIN_DIR" "$AGENTS_DIR" "$HOME/.aws" "$CONFIG_DIR"

for f in clipboard-monitor aws-from-clipboard aws-cred-process; do
    chmod +x "$PROJECT_DIR/bin/$f"
    ln -sfn "$PROJECT_DIR/bin/$f" "$BIN_DIR/$f"
    echo "  linked $BIN_DIR/$f → $PROJECT_DIR/bin/$f"
done

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$PROJECT_DIR/config/profiles.conf.sample" "$CONFIG_FILE"
    echo "  wrote   $CONFIG_FILE"
fi

# --- interactive loop ----------------------------------------------

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
        yn=""
        read -r yn </dev/tty || break
        case "$yn" in
            [yY]|[yY][eE][sS])
                add_mapping || true
                echo ""
                ;;
            *) break ;;
        esac
    done
fi

# --- write config, plist, load agent -------------------------------

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
done

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
