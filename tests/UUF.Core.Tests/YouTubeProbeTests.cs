using UUF.Core.Checking;
using Xunit;

namespace UUF.Core.Tests;

public class YouTubeProbeTests
{
    private const string ChannelPage = "{\"canonicalBaseUrl\":\"/@neo\",\"channelMetadataRenderer\":{\"title\":\"Neo\"}}";

    [Fact]
    public void ChannelWithMatchingCanonicalIsTaken()
    {
        var result = Probes.ClassifyYouTube(new HttpReply(200, ChannelPage), "neo");

        Assert.Equal(CheckStatus.Taken, result.Status);
    }

    [Fact]
    public void NotFoundPageIsFree()
    {
        var result = Probes.ClassifyYouTube(new HttpReply(404, string.Empty), "neo");

        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public void MismatchedCanonicalIsUnconfirmed()
    {
        var result = Probes.ClassifyYouTube(new HttpReply(200, "{\"canonicalBaseUrl\":\"/@other\",\"channelMetadataRenderer\":{}}"), "neo");

        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
    }

    [Fact]
    public async Task ProbeRequestsChannelHandleWithConsentCookie()
    {
        var transport = new FakeTransport(_ => new HttpReply(404, string.Empty));

        var result = await Probes.ProbeYouTubeAsync(transport, "neo", TimeSpan.FromSeconds(5), CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Equal("https://www.youtube.com/@neo", transport.Requests[0].Url);
        Assert.Equal("CONSENT=YES+cb; SOCS=CAI; GPS=1", transport.Requests[0].Headers["Cookie"]);
    }
}
