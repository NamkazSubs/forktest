# forktest

**English** | [Bahasa Indonesia](README.id.md)

A fork-based runner for **existing PHPUnit test suites**.

PHPUnit's `processIsolation` (and `@runTestsInSeparateProcesses`) gives every test its own PHP process, which is the
safe choice for suites that use Mockery `alias:`/`overload:`, statics or globals. It is also slow: each test spawns a
fresh `php`, boots the autoloader and re-parses the same files. On a suite with thousands of tests, most of the time
goes to starting processes, not to running tests.

forktest keeps the isolation and drops the startup cost. The parent process loads the bootstrap once and then
`pcntl_fork()`s one child per test. Tests are still executed by PHPUnit's own `TestCase::run()`, so `setUp`,
`tearDown`, assertions, data providers and Mockery behave as before. Only scheduling and isolation are different.

```
vendor/bin/forktest                      # run the suites from phpunit.xml
vendor/bin/forktest tests/Unit/Services  # run a directory or a file
vendor/bin/forktest --filter Transfer    # only tests whose name matches
vendor/bin/forktest --fast               # even faster, weaker isolation (see below)
```

## Results

Measured once on a Lumen 5.8 project (PHP 7.3.33, PHPUnit 7.0.0, 4 cores, 332 test files, 6,954 tests,
`processIsolation="true"`):

| Runner                           | Full suite            | Notes                                           |
|----------------------------------|-----------------------|-------------------------------------------------|
| `phpunit`                        | about 17 min          | extrapolated from a measured 445-test slice, not run in full |
| `paratest -p4`                   | 363 s                 | measured                                        |
| `forktest`                       | **48 s**              | measured, isolated per test                     |
| `forktest --fast`                | **22 s**              | measured, see the caveat below                  |

Every measured forktest run reported the same totals and the same set of failing tests as ParaTest
(6,954 tests, 14,453 assertions, 546 errors, 15 failures, 1 risky, 68 skipped; ParaTest counts the one risky test
as an error, hence 547 there). The full suite was compared with ParaTest only; plain `phpunit` was not run on it.
On a 445-test slice (`tests/Unit/Repositories`) that was run with `phpunit` itself (57.6 s vs 2.7 s for forktest),
the 14 failing tests were the same in both and fail for reasons unrelated to the runner (for example
`connection() on null`).

These are single runs on one machine. Expect about 10% noise, and different numbers on other suites.

## How it works

1. **Bootstrap once.** The parent reads `phpunit.xml`, applies its `<php>` section (env, ini, const, var, server),
   and requires the bootstrap file. It never loads test files.
2. **Discovery in children.** One child per file loads the file, builds PHPUnit's `TestSuite` (so data providers
   run) and reports the test names back.
3. **One fork per test.** Each test runs in its own child, which loads its own file, runs
   `TestCase::run()`, sends the outcome over a socket and exits. At most `--jobs` children run at once.
4. **Opcache.** `opcache.enable_cli` cannot be set with `ini_set()`, so forktest re-executes itself once with
   `-d opcache.enable_cli=1` when the extension is available. Forked children share the compiled scripts. Only
   forktest's own process tree is affected; `php.ini` and any running PHP-FPM or web app are untouched. Use
   `--no-opcache` to skip this.

Why the parent must not load test files or app classes: a test that uses Mockery `alias:` or `overload:` fails with
"class already exists" if the real class was already loaded before the fork. Keeping the parent clean is what makes
the isolation equivalent to a fresh process.

### `--fast`

With `--fast`, all tests of one file run sequentially in a single process, so each file costs one fork instead of
one per test. Files that contain `alias:`/`overload:` are still isolated per test, and if a shared worker dies
(for example on a fatal error) its unfinished tests are re-run isolated.

The trade-off: tests in one file can now see each other's static properties, globals and singletons, exactly like
plain PHPUnit without isolation. The suite above happened to give identical results in both modes, but the bundled
self-test contains two tests that deliberately depend on isolation and `--fast` fails one of them. Use `--fast` for
the edit-and-run loop and keep the default mode for CI.

## Requirements

- PHP 7.3 or newer with `pcntl` and `posix` (Linux or macOS; Windows is not supported).
- PHPUnit and the code under test installed in the project, loaded by the project's bootstrap or
  `vendor/autoload.php`.
- Optional: the `Zend OPcache` extension.

What has been tested:

| Combination                                   | What was checked                                                        |
|-----------------------------------------------|-------------------------------------------------------------------------|
| PHP 7.3.33 + PHPUnit 7.0.0, real 6,954-test suite | full run vs ParaTest: same totals and same failing tests            |
| PHP 7.4.33 + PHPUnit 7.0.0, same suite        | full run vs ParaTest: same except one opcache case (see below)          |
| PHP 7.3.33 + PHPUnit 7.5.20, bundled fixture  | `composer install`, selftest, totals equal to PHPUnit's own             |

forktest calls PHPUnit internals (`TestSuite`, `TestResult`, `PHPUnit\Util\Test::getHookMethods`), so PHPUnit 8 and
newer, and PHP 8, are untested and may not work.

## Install

Not on Packagist yet. Pick one:

**A. Composer, from the git repository**

```bash
composer config repositories.forktest vcs git@github.com:<your-account>/forktest.git
composer require --dev forktest/forktest:dev-main
vendor/bin/forktest
```

Before you push, replace the `forktest` vendor in `composer.json` and in the commands above with your own.

**B. Clone and run, no Composer**

```bash
git clone git@github.com:<your-account>/forktest.git ~/tools/forktest
cd /path/to/your/project
php ~/tools/forktest/bin/forktest
```

Optionally add `alias forktest='php ~/tools/forktest/bin/forktest'` to your shell profile.

forktest always runs from the project root (the directory that contains `phpunit.xml`).

## Usage

```
forktest [options] [path ...]

  path                  test file or directory (default: the testsuite directories of phpunit.xml)

  -j, --jobs N          parallel workers (default: number of CPU cores)
      --filter REGEX    only run tests whose name matches REGEX
      --group NAME      only run tests in this @group (comma separated, repeatable); a test without a group is
                        in the group "default"
      --exclude-group NAME
                        skip tests in this @group (comma separated, repeatable)
      --timeout SEC     kill a test that produces no result for SEC seconds (default 120)
      --stop-on-failure stop at the first error or failure (also on with stopOnFailure="true" in phpunit.xml)
      --log-junit FILE  write a JUnit XML report to FILE
      --fast            one process per file instead of one per test (see above)
      --preload         load PHPUnit/Mockery classes once in the parent before forking
      --no-opcache      do not enable opcache for the run
      --bootstrap FILE  bootstrap file (default: "bootstrap" from phpunit.xml, else vendor/autoload.php)
      --list            list discovered tests and exit
  -v, --verbose         full log: complete message and stack trace of failing tests, plus the skipped,
                        incomplete and risky tests
  -h, --help            show help
      --version         show version
```

Exit code: `0` when nothing failed or errored (skipped and incomplete tests are fine), `1` otherwise, `2` on usage
errors.

`--filter` is an unanchored PHP regular expression matched against the test name as PHPUnit prints it
(`Namespace\Class::method with data set #0`). Examples: `--filter TransferOwnership`, `--filter '::testRejects'`.

`--preload` ran with identical results in the benchmark but did not make the run measurably faster once opcache
was on, so it is off by default.

## Logging

The default output is lean on purpose, because forktest is about speed: one letter per test
(`.` pass, `E` error, `F` failure, `W` warning, `S` skipped, `I` incomplete, `R` risky), then each failing test with the
first two lines of its message, and a one-line summary. Everything below is opt-in.

- `-v` prints the complete message and the filtered stack trace of every failing test, and lists the skipped,
  incomplete and risky tests with their messages.
- `--log-junit FILE` writes a JUnit XML report (`testsuites > testsuite` per class `> testcase`, with `failure`,
  `error` and `skipped` elements, `classname`, `file`, `time` and `assertions`). Warnings are written as `error`,
  incomplete tests as `skipped`, and risky tests as passing, so the totals match the summary line.
- `--stop-on-failure` stops at the first error or failure and says how many tests were not run. Tests that were
  already running are killed.

Cost on the 6,954-test suite (single runs): default 48.5 s, `-v` 49.1 s, `--log-junit` 51.9 s (a 3 MB report).
Stack traces are only built when `-v` or `--log-junit` is used, so the default run does the same work as before.

## Known difference: opcache and compile-time diagnostics

With opcache on (the default), a compile-time warning or deprecation, such as PHP 7.4's
"Unparenthesized `a ? b : c ? d : e` is deprecated", is not raised inside the test. It is printed raw to stderr and
PHPUnit does not turn it into a test error. Without opcache, PHPUnit converts it into an error, so a test that would
fail under plain PHPUnit or ParaTest can pass under forktest.

On the 6,954-test suite this changed nothing on PHP 7.3 and exactly one test on PHP 7.4 (the full run agreed
with ParaTest otherwise). If you rely on such diagnostics, for example while upgrading PHP, or on CI, run with
`--no-opcache`. That costs about 2.4x (118 s instead of 48 s on the suite above) and restores the plain behavior.

## What it does not do (yet)

- No code coverage, no TestDox/JSON logging, no random order. (JUnit XML, `--group` and `--exclude-group` are
  supported.)
- No `@depends`. Every test runs in its own process, so a test that depends on another test's result is not
  supported. The suite it was developed on has none; this has not been tested.
- From `phpunit.xml` it reads only `bootstrap`, `stopOnFailure`, the `<php>` section and the testsuite
  `<directory>`/`<file>` entries (with `suffix`). Settings such as `processIsolation`, `backupGlobals`,
  `<exclude>`, `<listeners>` and `<filter>` are ignored.
- `setUpBeforeClass` and `tearDownAfterClass` run once per test, not once per class, in both modes.
- Output printed by tests is discarded. A failing test shows the first two lines of its message unless you pass `-v`.
- A test that produces no result for 120 s (change it with `--timeout`) is killed and reported as an error.

## Development

```bash
composer install
composer selftest            # or: bash scripts/selftest.sh [path/to/vendor/autoload.php]
```

`scripts/selftest.sh` runs `tests/fixtures/ControlTest.php`, a file of deliberately broken tests (failed assertion,
exception, unmet Mockery expectation, PHP notice, fatal error, skipped, incomplete, data providers, state leak), and
checks that forktest reports the same totals PHPUnit does (13 tests, 8 assertions, 4 errors, 2 failures, 1 skipped,
1 incomplete). It also checks `--filter`, `--group`, `--exclude-group`, `--stop-on-failure`, `--log-junit` (valid XML,
same totals) and `--timeout` (against `tests/fixtures/SlowTest.php`). Do not put `tests/fixtures` into a
`phpunit.xml` testsuite.

When changing the runner, compare against PHPUnit or ParaTest on a real suite before trusting a speedup: a faster
run only counts when the totals and the set of failing tests are unchanged. Two bugs found that way so far were a
parent that loaded app classes during discovery (Mockery "class already exists" errors) and `--list` executing
tests in `--fast` mode.
