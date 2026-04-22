#!/bin/bash
# Guards the clipboard-monitor detection predicate. Commit 4e8a98e
# replaced two `grep -q` subprocesses with a single bash [[ == *...* ]]
# test; the boolean outcome must stay identical.
set -euo pipefail

detect() {
    local current="$1"
    [[ "$current" == *"AWS_ACCESS_KEY_ID"* && "$current" == *"AWS_SECRET_ACCESS_KEY"* ]]
}

# Positive cases — these must trigger a login
detect 'export AWS_ACCESS_KEY_ID=AKIAX
export AWS_SECRET_ACCESS_KEY=sekr1t' || { echo "standard block"; exit 1; }

detect 'prefix AWS_ACCESS_KEY_ID=X ... AWS_SECRET_ACCESS_KEY=Y suffix' \
    || { echo "inline"; exit 1; }

# Negative cases — these must not trigger
if detect ''; then echo "empty"; exit 1; fi
if detect 'hello world'; then echo "random"; exit 1; fi
if detect 'only AWS_ACCESS_KEY_ID=X'; then echo "half1"; exit 1; fi
if detect 'only AWS_SECRET_ACCESS_KEY=Y'; then echo "half2"; exit 1; fi

# Parity check: the old two-grep predicate should agree on the same
# inputs. If this ever diverges, we've regressed the detection contract.
old_detect() {
    local current="$1"
    echo "$current" | grep -q "AWS_ACCESS_KEY_ID" && \
    echo "$current" | grep -q "AWS_SECRET_ACCESS_KEY"
}

samples=(
    ''
    'random'
    'export AWS_ACCESS_KEY_ID=X'
    'export AWS_SECRET_ACCESS_KEY=Y'
    'export AWS_ACCESS_KEY_ID=X
export AWS_SECRET_ACCESS_KEY=Y'
    'inline AWS_ACCESS_KEY_ID=X AWS_SECRET_ACCESS_KEY=Y more'
)
for s in "${samples[@]}"; do
    if detect "$s"; then new=1; else new=0; fi
    if old_detect "$s"; then old=1; else old=0; fi
    [ "$new" = "$old" ] || { echo "divergence on: $s (new=$new old=$old)"; exit 1; }
done

echo "cred detection: OK"
