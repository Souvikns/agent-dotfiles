#!/bin/sh
# tests/run.sh — run every tests/test_*.sh, report, exit non-zero on failure.
# Each file runs in its own `sh` process, so a test that leaves a sandbox behind
# or exports a stray variable cannot contaminate the next one.
set -u
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

total=0
failed=0
for t in test_*.sh; do
    [ -e "$t" ] || continue
    printf '%s\n' "$t"
    out=$(sh "$t" 2>&1); rc=$?
    printf '%s\n' "$out"
    n=$(printf '%s\n' "$out" | grep -c '^  ok   \|^  FAIL ' || true)
    f=$(printf '%s\n' "$out" | grep -c '^  FAIL ' || true)
    total=$((total + n))
    failed=$((failed + f))
    # A file that dies before asserting reports no failures; without this the
    # suite would pass silently on a crashed test.
    if [ "$rc" -ne 0 ]; then
        printf '  ERROR %s exited %s before finishing\n' "$t" "$rc"
        failed=$((failed + 1))
    fi
done

printf '\n%s assertions, %s failed\n' "$total" "$failed"
[ "$failed" -eq 0 ]
