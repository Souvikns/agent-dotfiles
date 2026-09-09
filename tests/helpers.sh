# tests/helpers.sh — a minimal POSIX assertion harness.
# Deliberately not bats-core: this keeps the repository at exactly one hard
# dependency (jq) across all three machines.

TESTS_RUN=0
TESTS_FAILED=0

_pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  ok   %s\n' "$1"; }
_fail() {
    TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL %s\n' "$1"
    shift
    for _l in "$@"; do printf '       %s\n' "$_l"; done
}

assert_eq() {  # MSG EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then _pass "$1"
    else _fail "$1" "expected: $2" "actual:   $3"; fi
}

# Output is captured so a failing command's diagnostics land in the report
# rather than scrolling past.
assert_ok() {  # MSG CMD...
    _m=$1; shift
    if _out=$("$@" 2>&1); then _pass "$_m"
    else _fail "$_m" "command failed: $*" "$_out"; fi
}

assert_fail() {  # MSG CMD...
    _m=$1; shift
    if _out=$("$@" 2>&1); then _fail "$_m" "expected failure, got success: $*" "$_out"
    else _pass "$_m"; fi
}

assert_file() {  # MSG PATH
    if [ -e "$2" ]; then _pass "$1"; else _fail "$1" "missing path: $2"; fi
}

assert_link() {  # MSG LINK EXPECTED_TARGET
    if [ ! -L "$2" ]; then _fail "$1" "not a symlink: $2"; return; fi
    _t=$(readlink "$2")
    if [ "$_t" = "$3" ]; then _pass "$1"
    else _fail "$1" "link target expected: $3" "link target actual:   $_t"; fi
}
