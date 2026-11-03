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

grp=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" --group marked "$FIX" 2>/dev/null | grep -a '^Tests:')
check "--group selects only tagged tests" "Tests: 1, Assertions: 1." "$grp"

exc=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" --exclude-group marked "$FIX" 2>/dev/null | grep -a '^Tests:')
check "--exclude-group skips tagged tests" "Tests: 12," "$exc"

stp=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" -j1 --stop-on-failure "$FIX" 2>/dev/null | grep -a '^Stopped')
check "--stop-on-failure stops early" "Stopped at the first failure" "$stp"

JX="$(mktemp)"; trap 'rm -f "$JX"' EXIT
php "$HERE/bin/forktest" --bootstrap "$BOOT" --log-junit "$JX" "$FIX" >/dev/null 2>&1
jx=$(php -r '$x = @simplexml_load_file($argv[1]); if (!$x) { echo "invalid"; exit; } $s = $x->testsuite; echo "tests=$s[tests] errors=$s[errors] failures=$s[failures] skipped=$s[skipped] cases=" . count($x->xpath("//testcase"));' "$JX")
check "--log-junit writes valid XML with the same totals" "tests=13 errors=4 failures=2 skipped=2 cases=13" "$jx"

start=$(date +%s)
slow=$(php "$HERE/bin/forktest" --bootstrap "$BOOT" --timeout 1 "$HERE/tests/fixtures/SlowTest.php" 2>/dev/null | grep -a '^Tests:')
took=$(( $(date +%s) - start ))
check "--timeout kills a hanging test" "Tests: 2, Assertions: 1, Errors: 1." "$slow"
if [ "$took" -lt 15 ]; then echo "ok    --timeout returned in ${took}s (test sleeps 30s)"; else echo "FAIL  --timeout took ${took}s"; fail=1; fi

# --- impact selection, in a throwaway git repo -------------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; rm -f "$JX"' EXIT
mkdir -p "$TMP/src" "$TMP/tests"
cat > "$TMP/src/Calc.php" <<'PHP'
<?php
class Calc { public function add($a, $b) { return $a + $b; } }
PHP
cat > "$TMP/tests/CalcTest.php" <<'PHP'
<?php
require_once __DIR__ . '/../src/Calc.php';
class CalcTest extends \PHPUnit\Framework\TestCase { public function testAdd() { $this->assertSame(3, (new Calc)->add(1, 2)); } }
PHP
cat > "$TMP/tests/OtherTest.php" <<'PHP'
<?php
class OtherTest extends \PHPUnit\Framework\TestCase { public function testOther() { $this->assertTrue(true); } }
PHP
cat > "$TMP/phpunit.xml" <<XML
<phpunit bootstrap="$BOOT"><testsuites><testsuite name="t"><directory suffix="Test.php">tests</directory></testsuite></testsuites></phpunit>
XML
echo "docs" > "$TMP/README.txt"
( cd "$TMP" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm base )
( cd "$TMP" && php "$HERE/bin/forktest" --record-map .forktest/map.json >/dev/null 2>&1 )
ft() { ( cd "$TMP" && php "$HERE/bin/forktest" "$@" 2>&1 ); }

echo "// touched" >> "$TMP/src/Calc.php"
sel=$(ft --changed --since HEAD --list | grep -a '^ - ')
check "impact: a changed source file selects only the test that loads it" " - CalcTest::testAdd" "$sel"
[[ "$sel" != *OtherTest* ]] && echo "ok    impact: the unrelated test is not selected" || { echo "FAIL  impact: OtherTest was selected"; fail=1; }
( cd "$TMP" && git checkout -q -- src/Calc.php )

echo "more docs" >> "$TMP/README.txt"
none=$(ft --changed --since HEAD)
check "impact: a docs-only change selects nothing" "No test files are affected" "$none"
( cd "$TMP" && git checkout -q -- README.txt )

echo '{}' > "$TMP/composer.json"
all=$(ft --changed --since HEAD)
check "impact: composer.json selects everything" "selected 2 of 2 test files (ALL: composer.json changed)" "$all"
rm -f "$TMP/composer.json"

cat > "$TMP/tests/NewTest.php" <<'PHP'
<?php
class NewTest extends \PHPUnit\Framework\TestCase { public function testNew() { $this->assertTrue(true); } }
PHP
new=$(ft --changed --since HEAD --list | grep -a '^ - ')
check "impact: a test file that is not in the map is always selected" " - NewTest::testNew" "$new"
rm -f "$TMP/tests/NewTest.php"

rc=$(cd "$TMP" && php "$HERE/bin/forktest" --record-map .forktest/m2.json --filter x >/dev/null 2>&1; echo $?)
check "--record-map refuses partial runs" "2" "$rc"

exit $fail
