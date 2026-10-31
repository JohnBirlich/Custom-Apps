using System.Collections.Concurrent;
using System.Net.Http;
using UUF.Core.Checking;
using UUF.Core.Transport;
using Xunit;

namespace UUF.Core.Tests;

internal sealed class FakeTransport : IHttpTransport
{
    private readonly Func<HttpRequestSpec, HttpReply> _respond;

    public FakeTransport(Func<HttpRequestSpec, HttpReply> respond)
    {
        _respond = respond;
    }

    public List<HttpRequestSpec> Requests { get; } = new();

    public Task<HttpReply> SendAsync(HttpRequestSpec request, CancellationToken cancellationToken)
    {
        Requests.Add(new HttpRequestSpec(request.Url, request.Method,
            new Dictionary<string, string>(request.Headers), request.Body, request.ContentType, request.Timeout));
        return Task.FromResult(_respond(request));
    }
}

public class CheckRunnerTests
{
    private static readonly TimeSpan Limit = TimeSpan.FromSeconds(10);

    private static IEnumerable<CheckJob> Jobs(int count) =>
        Enumerable.Range(0, count).Select(i => new CheckJob("name" + i, "Steam"));

    private static NameProbe Instant(CheckStatus status) =>
        (_, _) => Task.FromResult(new ProbeResult(status, "ok"));

    [Fact]
    public async Task NeverExceedsConfiguredThreadCount()
    {
        var running = 0;
        var maxRunning = 0;
        var reported = new ConcurrentBag<string>();
        NameProbe probe = async (name, ct) =>
        {
            var now = Interlocked.Increment(ref running);
            InterlockedMax(ref maxRunning, now);
            await Task.Delay(5, ct);
            Interlocked.Decrement(ref running);
            return new ProbeResult(CheckStatus.Free, "ok");
        };
        var runner = new CheckRunner(3);

        await runner.RunAsync(Jobs(20), _ => probe, new PauseController(),
            (job, _) => reported.Add(job.Name), CancellationToken.None);

        Assert.True(maxRunning <= 3, "максимум одновременных проверок: " + maxRunning);
        Assert.Equal(20, reported.Count);
        Assert.Equal(20, reported.Distinct().Count());
    }

    [Fact]
    public void ThreadCountIsClampedToSupportedRange()
    {
        Assert.Equal(CheckRunner.MaxThreads, new CheckRunner(100).Threads);
        Assert.Equal(CheckRunner.MinThreads, new CheckRunner(0).Threads);
    }

    [Fact]
    public async Task PauseHoldsNewChecksUntilResume()
    {
        var started = 0;
        NameProbe probe = (_, _) =>
        {
            Interlocked.Increment(ref started);
            return Task.FromResult(new ProbeResult(CheckStatus.Taken, "ok"));
        };
        var pause = new PauseController();
        pause.Pause();
        var reported = 0;
        var run = new CheckRunner(2).RunAsync(Jobs(5), _ => probe, pause,
            (_, _) => Interlocked.Increment(ref reported), CancellationToken.None);

        await Task.Delay(200);
        Assert.Equal(0, started);
        Assert.True(pause.IsPaused);

        pause.Resume();
        await run.WaitAsync(Limit);

        Assert.Equal(5, started);
        Assert.Equal(5, reported);
        Assert.False(pause.IsPaused);
    }

    [Fact]
    public async Task CancellationStopsRunWithoutReportingUnfinishedJobs()
    {
        using var cts = new CancellationTokenSource();
        var firstStarted = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reported = 0;
        NameProbe probe = async (_, ct) =>
        {
            firstStarted.TrySetResult(true);
            await Task.Delay(Timeout.Infinite, ct);
            return new ProbeResult(CheckStatus.Free, "never");
        };
        var run = new CheckRunner(1).RunAsync(Jobs(10), _ => probe, new PauseController(),
            (_, _) => Interlocked.Increment(ref reported), cts.Token);

        await firstStarted.Task.WaitAsync(Limit);
        cts.Cancel();
        await run.WaitAsync(Limit);

        Assert.Equal(0, reported);
    }

    [Fact]
    public async Task ProbeExceptionBecomesNetworkErrorResult()
    {
        NameProbe probe = (_, _) => throw new InvalidOperationException("boom");
        ProbeResult? captured = null;

        await new CheckRunner(1).RunAsync(Jobs(1), _ => probe, new PauseController(),
            (_, result) => captured = result, CancellationToken.None);

        Assert.NotNull(captured);
        Assert.Equal(CheckStatus.NetworkError, captured!.Status);
        Assert.Equal("boom", captured.Reason);
    }

    [Fact]
    public async Task ResultsAreAssignedToTheirOwnJob()
    {
        var jobs = new[] { new CheckJob("a", "Steam"), new CheckJob("b", "Steam") };
        var byName = new ConcurrentDictionary<string, CheckStatus>();

        await new CheckRunner(2).RunAsync(jobs,
            job => job.Name == "a" ? Instant(CheckStatus.Free) : Instant(CheckStatus.Taken),
            new PauseController(),
            (job, result) => byName[job.Name] = result.Status,
            CancellationToken.None);

        Assert.Equal(CheckStatus.Free, byName["a"]);
        Assert.Equal(CheckStatus.Taken, byName["b"]);
    }

    private static void InterlockedMax(ref int target, int candidate)
    {
        int current;
        do
        {
            current = Volatile.Read(ref target);
            if (candidate <= current) return;
        }
        while (Interlocked.CompareExchange(ref target, candidate, current) != current);
    }
}

public class ProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [Fact]
    public async Task RobloxRetriesOnceWithCsrfTokenFromForbiddenReply()
    {
        var calls = 0;
        var transport = new FakeTransport(_ =>
        {
            calls++;
            if (calls == 1)
            {
                return new HttpReply(403, string.Empty,
                    new Dictionary<string, string> { ["X-CSRF-Token"] = "tok123" });
            }
            return new HttpReply(200, "{\"code\":0}");
        });

        var result = await Probes.ProbeRobloxAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Equal(2, transport.Requests.Count);
        Assert.Equal("tok123", transport.Requests[1].Headers["X-CSRF-Token"]);
        Assert.False(transport.Requests[0].Headers.ContainsKey("X-CSRF-Token"));
    }

    [Fact]
    public async Task RobloxForbiddenWithoutTokenIsNotRetriedAndNotFree()
    {
        var transport = new FakeTransport(_ => new HttpReply(403, string.Empty));

        var result = await Probes.ProbeRobloxAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
        Assert.Single(transport.Requests);
    }

    [Fact]
    public async Task RobloxSendsPostWithSignupPayload()
    {
        var transport = new FakeTransport(_ => new HttpReply(200, "{\"code\":1}"));

        var result = await Probes.ProbeRobloxAsync(transport, "neo", Timeout, CancellationToken.None);

        var request = Assert.Single(transport.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://auth.roblox.com/v1/usernames/validate", request.Url);
        Assert.Contains("\"username\":\"neo\"", request.Body);
        Assert.Equal(CheckStatus.Taken, result.Status);
    }

    [Fact]
    public async Task TelegramStopsAtFirstDecisiveMirror()
    {
        var transport = new FakeTransport(request =>
            request.Url.StartsWith("https://t.me/")
                ? new HttpReply(200, "<div class=\"tgme_page_title\"><span>Neo</span></div>")
                : new HttpReply(404, string.Empty));

        var result = await Probes.ProbeTelegramAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Single(transport.Requests);
    }

    [Fact]
    public async Task TelegramPageWithoutProfileOnAllMirrorsIsFree()
    {
        var transport = new FakeTransport(_ => new HttpReply(200, "<html>nothing here</html>"));

        var result = await Probes.ProbeTelegramAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Equal(3, transport.Requests.Count);
    }

    [Fact]
    public async Task TelegramUnreachableEverywhereIsUnconfirmed()
    {
        var transport = new FakeTransport(_ => new HttpReply(0, string.Empty));

        var result = await Probes.ProbeTelegramAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
        Assert.Contains("Прокси", result.Reason);
    }

    [Fact]
    public async Task UnknownPlatformIsUnconfirmedWithoutNetworkCalls()
    {
        var transport = new FakeTransport(_ => throw new InvalidOperationException("must not be called"));
        var probe = Probes.For("Неизвестная", transport, Timeout);

        var result = await probe("neo", CancellationToken.None);

        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
        Assert.Empty(transport.Requests);
    }
}
