#!/bin/bash
# Runs every test_*.sh in this directory. Each test script exits 0 on
# success, non-zero on failure, and prints a summary line like
# "<name>: OK" as its last stdout line.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

pass=0
fail=0
failed_names=()

for t in test_*.sh; do
    [ -e "$t" ] || continue
    out=$(bash "$t" 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then
        printf '  ✓ %s\n' "$t"
        pass=$((pass+1))
    else
        printf '  ✗ %s (exit %d)\n' "$t" "$rc"
        printf '%s\n' "$out" | sed 's/^/      /'
        fail=$((fail+1))
        failed_names+=("$t")
    fi
done

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ]
