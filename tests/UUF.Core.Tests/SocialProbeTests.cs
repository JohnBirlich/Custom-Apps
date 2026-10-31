using UUF.Core.Checking;
using Xunit;

namespace UUF.Core.Tests;

public class VkProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [Fact]
    public async Task ResolvedScreenNameIsTakenWithoutProfileRequest()
    {
        var transport = new FakeTransport(_ => new HttpReply(200, "{\"response\":{\"object_id\":42,\"type\":\"user\"}}"));

        var result = await Probes.ProbeVkAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Single(transport.Requests);
    }

    [Fact]
    public async Task NullResponseIsFreeWithoutProfileRequest()
    {
        var transport = new FakeTransport(_ => new HttpReply(200, "{\"response\":null}"));

        var result = await Probes.ProbeVkAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Single(transport.Requests);
    }

    [Fact]
    public async Task EmptyApiAnswerFallsBackToProfilePage()
    {
        var transport = new FakeTransport(request =>
            request.Url.StartsWith("https://api.vk.com/")
                ? new HttpReply(200, "{}")
                : new HttpReply(200, "<div id=\"profile_short\">Neo</div>"));

        var result = await Probes.ProbeVkAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Equal(2, transport.Requests.Count);
    }

    [Fact]
    public async Task ProfileNotFoundIsFree()
    {
        var transport = new FakeTransport(request =>
            request.Url.StartsWith("https://api.vk.com/")
                ? new HttpReply(200, "{}")
                : new HttpReply(404, string.Empty));

        var result = await Probes.ProbeVkAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public async Task ApiErrorStatusIsNetworkError()
    {
        var transport = new FakeTransport(_ => new HttpReply(500, string.Empty));

        var result = await Probes.ProbeVkAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.NetworkError, result.Status);
    }
}

public class DiscordProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [Fact]
    public async Task NameIsSentLowercased()
    {
        var transport = new FakeTransport(_ => new HttpReply(200, "{\"taken\":false}"));

        var result = await Probes.ProbeDiscordAsync(transport, "NeO", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Contains("\"username\":\"neo\"", transport.Requests[0].Body);
    }

    [Fact]
    public void TakenFlagIsTaken()
    {
        Assert.Equal(CheckStatus.Taken, Probes.ClassifyDiscord(new HttpReply(200, "{\"taken\":true}")).Status);
    }

    [Fact]
    public void UsernameTakenMessageIsTaken()
    {
        var result = Probes.ClassifyDiscord(new HttpReply(200, "{\"message\":\"Username is taken\"}"));
        Assert.Equal(CheckStatus.Taken, result.Status);
    }

    [Fact]
    public void BadFormatIsInvalid()
    {
        Assert.Equal(CheckStatus.Invalid, Probes.ClassifyDiscord(new HttpReply(400, string.Empty)).Status);
        Assert.Equal(CheckStatus.Invalid, Probes.ClassifyDiscord(new HttpReply(422, string.Empty)).Status);
    }

    [Fact]
    public void UnexpectedBodyIsUnconfirmedNotFree()
    {
        Assert.Equal(CheckStatus.Unconfirmed, Probes.ClassifyDiscord(new HttpReply(200, "{}")).Status);
        Assert.Equal(CheckStatus.Unconfirmed, Probes.ClassifyDiscord(new HttpReply(200, "не json")).Status);
    }

    [Fact]
    public void RateLimitIsNetworkError()
    {
        Assert.Equal(CheckStatus.NetworkError, Probes.ClassifyDiscord(new HttpReply(429, string.Empty)).Status);
    }
}

public class MailRuProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [Theory]
    [InlineData("{\"body\":{\"exists\":true}}", CheckStatus.Taken)]
    [InlineData("{\"body\":{\"exists\":false}}", CheckStatus.Free)]
    [InlineData("{\"exists\":true}", CheckStatus.Taken)]
    [InlineData("{\"other\":1}", CheckStatus.Unconfirmed)]
    public async Task ReadsExistsFlag(string body, CheckStatus expected)
    {
        var transport = new FakeTransport(_ => new HttpReply(200, body));

        var result = await Probes.ProbeMailRuAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(expected, result.Status);
        Assert.Contains("neo%40mail.ru", transport.Requests[0].Url);
    }

    [Fact]
    public async Task NonOkStatusIsNetworkError()
    {
        var transport = new FakeTransport(_ => new HttpReply(503, string.Empty));

        var result = await Probes.ProbeMailRuAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.NetworkError, result.Status);
    }
}
