using UUF.Core.Checking;
using Xunit;

namespace UUF.Core.Tests;

public class GitHubProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    private static FakeTransport Route(HttpReply check, HttpReply? api = null)
    {
        return new FakeTransport(request =>
            request.Url.StartsWith("https://api.github.com/", StringComparison.Ordinal)
                ? api ?? new HttpReply(404, string.Empty)
                : request.Url.Contains("signup_check", StringComparison.Ordinal)
                    ? check
                    : new HttpReply(200, string.Empty));
    }

    [Fact]
    public async Task EmptySignupCheckIsFreeAfterSessionInit()
    {
        var transport = Route(new HttpReply(200, string.Empty));

        var result = await Probes.ProbeGitHubAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Equal(2, transport.Requests.Count);
    }

    [Fact]
    public async Task TakenNameFromSignupCheckIsTaken()
    {
        var transport = Route(new HttpReply(422, "Username is already taken"));

        var result = await Probes.ProbeGitHubAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
    }

    [Fact]
    public async Task ReservedNameFromSignupCheckIsInvalid()
    {
        var transport = Route(new HttpReply(403, "Username is a reserved word"));

        var result = await Probes.ProbeGitHubAsync(transport, "admin", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Invalid, result.Status);
    }

    [Fact]
    public async Task InconclusiveSignupFallsBackToApi()
    {
        var transport = Route(new HttpReply(500, "oops"), new HttpReply(200, "{}"));

        var result = await Probes.ProbeGitHubAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Equal(3, transport.Requests.Count);
    }

    [Fact]
    public async Task ApiNotFoundIsFree()
    {
        var transport = Route(new HttpReply(500, "oops"), new HttpReply(404, "{}"));

        var result = await Probes.ProbeGitHubAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public void ApiForbiddenIsNetworkError()
    {
        var result = Probes.ClassifyGitHubApi(new HttpReply(403, "{}"));

        Assert.Equal(CheckStatus.NetworkError, result.Status);
    }

    [Fact]
    public void UnknownApiAnswerIsNetworkError()
    {
        var result = Probes.ClassifyGitHubApi(new HttpReply(500, "{}"));

        Assert.Equal(CheckStatus.NetworkError, result.Status);
        Assert.False(result.StopRun);
    }

    [Fact]
    public void ApiForbiddenStopsRun()
    {
        var result = Probes.ClassifyGitHubApi(new HttpReply(403, "{}"));

        Assert.True(result.StopRun);
    }

    [Fact]
    public void ExhaustedRateLimitStopsRunAfterAnswer()
    {
        var headers = new Dictionary<string, string> { ["X-RateLimit-Remaining"] = "0" };

        var result = Probes.ClassifyGitHubApi(new HttpReply(200, "{}", headers));

        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.True(result.StopRun);
    }

    [Fact]
    public void RemainingRateLimitDoesNotStopRun()
    {
        var headers = new Dictionary<string, string> { ["X-RateLimit-Remaining"] = "42" };

        var result = Probes.ClassifyGitHubApi(new HttpReply(404, "{}", headers));

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.False(result.StopRun);
    }
}
