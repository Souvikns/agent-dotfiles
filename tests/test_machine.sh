#!/bin/sh
set -u
. ./helpers.sh
. ./sandbox.sh
. ../scripts/lib/common.sh
. ../scripts/lib/machine.sh

SB=$(sandbox_new); eval "$(sandbox_env "$SB")"

assert_fail "load fails before any name is recorded" ad_machine_load
assert_ok   "valid name accepted" ad_machine_valid wsl
assert_fail "name with a slash rejected" ad_machine_valid "bad/name"
assert_fail "empty name rejected" ad_machine_valid ""

ad_machine_save macos
assert_eq "load returns the saved name" "macos" "$(ad_machine_load)"
assert_eq "resolve with no argument reads the saved name" "macos" "$(ad_machine_resolve)"
assert_eq "resolve with an argument overrides" "linux" "$(ad_machine_resolve linux)"
assert_eq "an override persists for next time" "linux" "$(ad_machine_load)"

sandbox_rm "$SB"
