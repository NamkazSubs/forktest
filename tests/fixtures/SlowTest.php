<?php
namespace Forktest\Fixtures;

use PHPUnit\Framework\TestCase;

/** Used by scripts/selftest.sh to check --timeout. */
class SlowTest extends TestCase
{
    public function testFast() { $this->assertTrue(true); }
    public function testHangs() { sleep(30); $this->assertTrue(true); }
}
