#!/bin/bash
# Verifies aws-cred-process produces SDK-consumable JSON, both with and
# without a session token, and exits non-zero when the creds file is
# missing. Covers the python3→bash migration in commit 4e8a98e.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/aws-cred-process"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/.aws"

# Case 1: short-term creds (with session token)
cat > "$TMPDIR/.aws/session-creds-test.json" <<'EOF'
{
  "Version": 1,
  "AccessKeyId": "AKIATESTEXAMPLE",
  "SecretAccessKey": "testSecretKey1234567890",
  "SessionToken": "testSessionToken/with+slashes=and=equals"
}
EOF

out=$(HOME="$TMPDIR" bash "$SCRIPT" test)

# Must be valid JSON
echo "$out" | python3 -m json.tool >/dev/null

# Fields round-trip unchanged
py() { python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('$1',''))" <<< "$out"; }
[ "$(py Version)" = "1" ]
[ "$(py AccessKeyId)" = "AKIATESTEXAMPLE" ]
[ "$(py SecretAccessKey)" = "testSecretKey1234567890" ]
[ "$(py SessionToken)" = "testSessionToken/with+slashes=and=equals" ]

# Expiration present and looks like ISO-8601 UTC
exp=$(py Expiration)
[[ "$exp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]

# Case 2: long-term creds (no session token)
cat > "$TMPDIR/.aws/session-creds-longterm.json" <<'EOF'
{
  "Version": 1,
  "AccessKeyId": "AKIALONGTERM",
  "SecretAccessKey": "longSecret"
}
EOF
out=$(HOME="$TMPDIR" bash "$SCRIPT" longterm)
echo "$out" | python3 -m json.tool >/dev/null
[ "$(py AccessKeyId)" = "AKIALONGTERM" ]
# Must NOT include SessionToken
python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 'SessionToken' not in d, 'SessionToken should be absent for long-term creds'
" <<< "$out"

# Case 3: missing creds file → non-zero exit
if HOME="$TMPDIR" bash "$SCRIPT" doesnotexist >/dev/null 2>&1; then
    echo "expected non-zero exit for missing creds file" >&2
    exit 1
fi

echo "aws-cred-process: OK"
