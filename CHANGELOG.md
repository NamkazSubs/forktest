# Changelog

All notable changes to forktest are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/). While the version is below 1.0.0, options and output may still change.

## [Unreleased]

## [0.1.0] - 2026-11-03

First version. Not tagged or published yet.

### Added

- **Fork-based runner.** The parent process loads only the bootstrap file. Test files are loaded in forked children
  (one discovery child per file, then one child per test), so every test sees what a fresh `php` process would see and
  Mockery `alias:`/`overload:` keep working. Tests run through PHPUnit's own `TestCase::run()`.
- **`phpunit.xml` support:** `bootstrap`, the `<php>` section (`ini`, `const`, `var`, `server`, `env`, with `force`),
  `stopOnFailure`, and testsuite `<directory>`/`<file>` entries (with `suffix`).
- **Opcache for the CLI run.** forktest re-executes itself once with `-d opcache.enable_cli=1` when the extension is
  available; `--no-opcache` turns this off. `php.ini` and running web processes are not touched.
- **`--fast`:** one process per test file; files that use `alias:`/`overload:` stay isolated per test, and tests left
  behind by a worker that died are re-run isolated.
- **Selection and control:** `--jobs`/`-j`, `--filter`, `--group`, `--exclude-group`, `--list`, `--bootstrap`,
  `--preload`, `--timeout`, `--stop-on-failure`.
- **Logging (opt-in, the default output stays lean):** `-v` prints complete messages and filtered stack traces and lists
  skipped, incomplete and risky tests; `--log-junit FILE` writes a JUnit XML report.
- **Impact selection:** `--record-map FILE` records which project files each test file loads (from
  `get_included_files()` in each test process); `--changed` and `--since REF` run only the test files affected by the
  git diff; `--map FILE` picks the map; `--explain` prints why each test file was selected. Changes to `composer.*`,
  `phpunit.xml*`, `tests/bootstrap.php`, `.env*` or a file loaded by the bootstrap select everything; test files that
  are not in the map are always selected.
- `scripts/selftest.sh` and `tests/fixtures/`: 16 checks against deliberately broken tests, including a throwaway git
  repository for impact selection.
- README in English and Indonesian, `composer.json` with a `forktest` binary, MIT license.

### Measured

On a Lumen 5.8 suite with 6,954 tests (PHP 7.3.33, PHPUnit 7.0.0, 4 cores), single runs: `paratest -p4` 363 s,
`forktest` 48 s, `forktest --fast` 22 s, with the same totals and failing tests as ParaTest. `--changed` on a real
branch ran 509 tests in 4.6 s. Details and caveats are in the README.

### Known issues and limitations

- With opcache on, compile-time warnings and deprecations are not turned into test errors; use `--no-opcache` when you
  rely on them. One test differed on PHP 7.4 because of this.
- Not supported: code coverage, TestDox/JSON logs, random order, `@depends`, `<listeners>`, `processIsolation` from
  `phpunit.xml`. `setUpBeforeClass` and `tearDownAfterClass` run once per test.
- Impact selection sees only files loaded through PHP `include`/autoload; the map must be re-recorded after large
  merges.
- Tested only with PHP 7.3 and 7.4 and PHPUnit 7.0 and 7.5, on Linux. PHP 8 and PHPUnit 8 or newer are untested.

[Unreleased]: #
[0.1.0]: #
