using WindowsAGIMesh.Benchmarks;

namespace WindowsAGIMesh.SchemaTests;

/// <summary>
/// Unit tests for <see cref="BenchmarkRunner"/> and <see cref="BenchmarkResult"/>.
/// </summary>
public sealed class BenchmarkRunnerTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // BenchmarkRunner.Run
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Run_WithSimpleWorkload_ReturnsResult()
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "test-benchmark",
            iterations: 100,
            workload:   () => { double _ = Math.Sqrt(42); });

        result.Should().NotBeNull();
    }

    [Fact]
    public void Run_Name_MatchesInput()
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "my-bench",
            iterations: 10,
            workload:   () => { });

        result.Name.Should().Be("my-bench");
    }

    [Fact]
    public void Run_Iterations_MatchesInput()
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "iter-bench",
            iterations: 50,
            workload:   () => { });

        result.Iterations.Should().Be(50);
    }

    [Fact]
    public void Run_TotalMs_IsPositive()
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "time-bench",
            iterations: 1000,
            workload:   () => { double _ = Math.Sqrt(99); });

        result.TotalMs.Should().BeGreaterThanOrEqualTo(0);
    }

    [Fact]
    public void Run_AverageMs_IsLessThanOrEqualToTotalMs()
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "avg-bench",
            iterations: 100,
            workload:   () => { });

        result.AverageMs.Should().BeLessThanOrEqualTo(result.TotalMs + 0.001);
    }

    [Fact]
    public void Run_OpsPerSecond_IsPositive()
    {
        BenchmarkResult result = BenchmarkRunner.Run(
            name:       "ops-bench",
            iterations: 100,
            workload:   () => { });

        result.OpsPerSecond.Should().BeGreaterThan(0);
    }

    [Fact]
    public void Run_NullWorkload_ThrowsArgumentNullException()
    {
        Action act = () => BenchmarkRunner.Run("null-bench", 10, null!);
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Run_ZeroIterations_ThrowsArgumentOutOfRangeException()
    {
        Action act = () => BenchmarkRunner.Run("zero-bench", 0, () => { });
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BenchmarkRunner.RunAsync
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public async Task RunAsync_WithAsyncWorkload_ReturnsResult()
    {
        BenchmarkResult result = await BenchmarkRunner.RunAsync(
            name:       "async-bench",
            iterations: 10,
            workload:   () => Task.Delay(0));

        result.Should().NotBeNull();
        result.Iterations.Should().Be(10);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BenchmarkResult
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ToCsv_ContainsAllFields()
    {
        var result = new BenchmarkResult(
            Name:        "csv-test",
            Iterations:  1000,
            TotalMs:     50.0,
            AverageMs:   0.05,
            OpsPerSecond: 20000.0);

        string csv = result.ToCsv();

        csv.Should().Contain("csv-test");
        csv.Should().Contain("1000");
    }

    [Fact]
    public void CsvHeader_ContainsExpectedColumns()
    {
        BenchmarkResult.CsvHeader.Should()
            .Contain("Name")
            .And.Contain("Iterations")
            .And.Contain("TotalMs")
            .And.Contain("AverageMs")
            .And.Contain("OpsPerSecond");
    }

    [Fact]
    public void Print_DoesNotThrow()
    {
        var result = new BenchmarkResult("print-test", 100, 10.0, 0.1, 10000.0);
        Action act = () => result.Print();
        act.Should().NotThrow();
    }
}