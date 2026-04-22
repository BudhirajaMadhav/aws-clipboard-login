#!/bin/bash
# Exercises lookup_profile / lookup_region against a fixture
# profiles.conf. Guards the config-file awk parsing used by
# aws-from-clipboard to map account IDs to nicknames / regions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/aws-from-clipboard"

eval "$(awk '/^lookup_profile\(\) \{/,/^}$/' "$SCRIPT")"
eval "$(awk '/^lookup_region\(\) \{/,/^}$/'  "$SCRIPT")"

CONFIG_FILE=$(mktemp)
trap 'rm -f "$CONFIG_FILE"' EXIT
cat > "$CONFIG_FILE" <<'EOF'
# This line is a comment and must be ignored.
  # indented comment, also ignored
123456789012  dev      us-east-1
210987654321  prod     eu-west-1
999999999999  twoparts
EOF

[ "$(lookup_profile 123456789012)" = "dev" ]  || { echo "profile 123..."; exit 1; }
[ "$(lookup_profile 210987654321)" = "prod" ] || { echo "profile 210..."; exit 1; }
[ "$(lookup_profile 999999999999)" = "twoparts" ] || { echo "profile 999 (region omitted)"; exit 1; }
[ -z "$(lookup_profile 000000000000)" ] || { echo "profile 000 should be empty"; exit 1; }

[ "$(lookup_region 123456789012)" = "us-east-1" ]  || { echo "region 123..."; exit 1; }
[ "$(lookup_region 210987654321)" = "eu-west-1" ]  || { echo "region 210..."; exit 1; }
# 999 entry has only 2 fields → region lookup should return empty
[ -z "$(lookup_region 999999999999)" ] || { echo "region 999 should be empty"; exit 1; }
[ -z "$(lookup_region 000000000000)" ] || { echo "region 000 should be empty"; exit 1; }

echo "lookup: OK"
