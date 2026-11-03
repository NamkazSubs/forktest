#!/usr/bin/env bash
# Sanity check: forktest must classify a set of deliberately broken tests exactly like PHPUnit does.
# usage: scripts/selftest.sh [path/to/vendor/autoload.php]   (needs phpunit/phpunit 7 and mockery installed there)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BOOT="${1:-$HERE/vendor/autoload.php}"
FIX="$HERE/tests/fixtures/ControlTest.php"
fail=0

check() { # label, expected, actual
  if [[ "$3" == *"$2"* ]]; then echo "ok    $1"; else echo "FAIL  $1"; echo "      expected: $2"; echo "      actual:   $3"; fail=1; fi
}

iso=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" "$FIX" 2>/dev/null | grep -a '^Tests:')
check "isolated mode matches PHPUnit" "Tests: 13, Assertions: 8, Errors: 4, Failures: 2, Skipped: 1, Incomplete: 1." "$iso"

fast=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" --fast "$FIX" 2>/dev/null | grep -a '^Tests:')
check "--fast shows the documented state leak (one extra failure)" "Tests: 13, Assertions: 8, Errors: 4, Failures: 3, Skipped: 1, Incomplete: 1." "$fast"

one=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" --filter testPassing "$FIX" 2>/dev/null | grep -a '^Tests:')
check "--filter selects a single test" "Tests: 1, Assertions: 1." "$one"

php "$HERE/bin/forktest" --bootstrap "$BOOT" "$FIX" >/dev/null 2>&1; rc=$?
check "exit code is 1 when tests fail" "1" "$rc"

exit $fail
