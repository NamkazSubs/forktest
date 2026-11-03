<?php
namespace Forktest\Fixtures;

use PHPUnit\Framework\TestCase;

/**
 * Deliberately broken tests used by scripts/selftest.sh to check that forktest classifies outcomes the way
 * PHPUnit does. Do NOT put this folder in a phpunit.xml testsuite.
 */
class ControlTest extends TestCase
{
    public static $leak = 0;

    protected function tearDown(): void
    {
        \Mockery::close();
    }

    /** @group marked */
    public function testPassing() { $this->assertTrue(true); }
    public function testFailingAssert() { $this->assertSame(1, 2); }
    public function testThrows() { throw new \RuntimeException('boom'); }
    public function testSkipped() { $this->markTestSkipped('nope'); }
    public function testIncomplete() { $this->markTestIncomplete('todo'); }
    public function testUnmetMockExpectation()
    {
        $m = \Mockery::mock('Foo');
        $m->shouldReceive('bar')->once();
        $this->assertTrue(true);
    }
    public function testWarningNotice() { $x = []; $y = $x['missing']; $this->assertTrue(true); }
    public function testFatalCrash() { eval('function_that_does_not_exist_zzz();'); }
    // Both assert leak == 1: passes when every test has its own process, fails for the 2nd one when state is shared.
    public function testLeakA() { self::$leak++; $this->assertSame(1, self::$leak); }
    public function testLeakB() { self::$leak++; $this->assertSame(1, self::$leak); }
    /** @dataProvider provider */
    public function testData($a, $b) { $this->assertSame($a, $b); }
    public function provider() { return [[1, 1], [1, 2], 'named' => [3, 3]]; }
}
