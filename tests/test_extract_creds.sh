#!/bin/bash
# Exercises the extract_creds function from aws-from-clipboard without
# triggering the script's main flow. Uses awk-range extraction to pull
# the function out of the script, then evals it in a subshell.
#
# NB: we do NOT set -e / pipefail here. extract_creds contains
# `echo | grep | sed` pipelines that fail harmlessly when the pattern
# isn't present (e.g. long-term creds with no AWS_SESSION_TOKEN); the
# production script runs without strict flags and relies on that.
set -u
die() { echo "FAIL: $*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/aws-from-clipboard"

eval "$(awk '/^extract_creds\(\) \{/,/^}$/' "$SCRIPT")"

# Short-term creds (standard AWS SSO "copy command-line creds" output)
blob='export AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF
export AWS_SECRET_ACCESS_KEY=secret/with+special=chars
export AWS_SESSION_TOKEN=tokenWithLotsOf+/=Characters'
extract_creds "$blob" || die "should have returned true on full creds"
[ "$access_key"    = "AKIA1234567890ABCDEF" ]                  || die "access_key=$access_key"
[ "$secret_key"    = "secret/with+special=chars" ]             || die "secret_key=$secret_key"
[ "$session_token" = "tokenWithLotsOf+/=Characters" ]          || die "session_token=$session_token"

# Long-term creds (no session token)
blob='export AWS_ACCESS_KEY_ID=AKIALONGTERM
export AWS_SECRET_ACCESS_KEY=longSecret'
access_key="" secret_key="" session_token=""
extract_creds "$blob" || die "should have returned true on long-term creds"
[ "$access_key" = "AKIALONGTERM" ]  || die "long-term access_key=$access_key"
[ "$secret_key" = "longSecret" ]    || die "long-term secret_key=$secret_key"
[ -z "$session_token" ]             || die "long-term session_token not empty: $session_token"

# Missing both fields → function returns 1
access_key="" secret_key="" session_token=""
extract_creds "random text with no creds" && die "expected false for non-cred input"

# Missing secret only → function returns 1
access_key="" secret_key="" session_token=""
extract_creds "export AWS_ACCESS_KEY_ID=AKIA" && die "expected false when secret is missing"

echo "extract_creds: OK"
