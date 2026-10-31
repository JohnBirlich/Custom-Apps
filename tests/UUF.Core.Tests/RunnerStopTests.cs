using UUF.Core.Checking;
using Xunit;

namespace UUF.Core.Tests;

public class RunnerStopTests
{
    [Fact]
    public async Task StopRunSkipsRemainingJobs()
    {
        var reported = new List<string>();
        var probeCalls = 0;
        NameProbe probe = (name, _) =>
        {
            Interlocked.Increment(ref probeCalls);
            return Task.FromResult(name == "u0"
                ? new ProbeResult(CheckStatus.NetworkError, "limit", StopRun: true)
                : new ProbeResult(CheckStatus.Free, "ok"));
        };
        var jobs = Enumerable.Range(0, 5).Select(index => new CheckJob("u" + index, "GitHub")).ToList();

        await new CheckRunner(1).RunAsync(
            jobs,
            _ => probe,
            new PauseController(),
            (job, _) => reported.Add(job.Name),
            CancellationToken.None);

        Assert.Equal(new[] { "u0" }, reported);
        Assert.Equal(1, probeCalls);
    }

    [Fact]
    public async Task RunWithoutStopReportsEveryJob()
    {
        var reported = new List<string>();
        NameProbe probe = (_, _) => Task.FromResult(new ProbeResult(CheckStatus.Free, "ok"));
        var jobs = Enumerable.Range(0, 3).Select(index => new CheckJob("u" + index, "GitHub")).ToList();

        await new CheckRunner(2).RunAsync(
            jobs,
            _ => probe,
            new PauseController(),
            (job, _) => reported.Add(job.Name),
            CancellationToken.None);

        Assert.Equal(3, reported.Count);
    }
}
