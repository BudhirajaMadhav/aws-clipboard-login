#!/bin/bash
# End-to-end test of identify_account with a MOCK aws binary. Commit
# 4e8a98e changed the aws invocation from json+python3 parsing to
# text+tab-separated read; this test verifies account_id and arn still
# end up in the expected shell variables for both output styles.
#
# We avoid `set -e` so that an expected non-zero return from
# identify_account (invalid creds) doesn't tear down the test.
set -u
die() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/aws-from-clipboard"

# Stand up a fake PATH entry that intercepts `aws`.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

make_aws_stub() {  # $1 = stdout body
    cat > "$TMPDIR/aws" <<EOF
#!/bin/bash
# Stub — prints the fixture regardless of args.
cat <<'PAYLOAD'
$1
PAYLOAD
EOF
    chmod +x "$TMPDIR/aws"
}

eval "$(awk '/^lookup_profile\(\) \{/,/^}$/' "$SCRIPT")"
eval "$(awk '/^lookup_region\(\) \{/,/^}$/'  "$SCRIPT")"
eval "$(awk '/^identify_account\(\) \{/,/^}$/' "$SCRIPT")"

CONFIG_FILE=$(mktemp)
cat > "$CONFIG_FILE" <<'EOF'
123456789012  dev  us-west-2
EOF
DEFAULT_REGION="us-east-1"

# Case 1: text mode, tab-separated (commit 4e8a98e's --output text --query '[Account,Arn]')
make_aws_stub $'123456789012\tarn:aws:iam::123456789012:user/alice'
access_key="AKIA" secret_key="sec" session_token="tok"
account_id="" arn="" profile_name="" profile_region=""
PATH="$TMPDIR:$PATH" identify_account || die "identify_account should have succeeded"
[ "$account_id"     = "123456789012" ]                         || die "account_id=$account_id"
[ "$arn"            = "arn:aws:iam::123456789012:user/alice" ] || die "arn=$arn"
[ "$profile_name"   = "dev" ]                                  || die "profile_name=$profile_name"
[ "$profile_region" = "us-west-2" ]                            || die "profile_region=$profile_region"

# Case 2: unmapped account → profile falls back to account ID, region to default
make_aws_stub $'999999999999\tarn:aws:iam::999999999999:user/bob'
access_key="AKIA" secret_key="sec" session_token="tok"
account_id="" arn="" profile_name="" profile_region=""
PATH="$TMPDIR:$PATH" identify_account || die "identify_account should have succeeded for unmapped"
[ "$account_id"     = "999999999999" ] || die "unmapped account_id=$account_id"
[ "$profile_name"   = "999999999999" ] || die "unmapped profile_name=$profile_name"
[ "$profile_region" = "us-east-1" ]    || die "unmapped profile_region=$profile_region"

# Case 3: aws exits non-zero (invalid creds) → identify_account returns 1
cat > "$TMPDIR/aws" <<'EOF'
#!/bin/bash
exit 255
EOF
chmod +x "$TMPDIR/aws"
access_key="AKIA" secret_key="sec" session_token="tok"
if PATH="$TMPDIR:$PATH" identify_account 2>/dev/null; then
    die "identify_account should fail on invalid creds"
fi

echo "identify_account: OK"
