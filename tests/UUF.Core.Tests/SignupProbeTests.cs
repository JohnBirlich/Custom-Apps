using UUF.Core.Checking;
using Xunit;

namespace UUF.Core.Tests;

public class GoogleProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [Fact]
    public async Task LookupCode105IsFree()
    {
        var transport = new FakeTransport(request =>
            request.Url.Contains("signin/sl/lookup", StringComparison.Ordinal)
                ? new HttpReply(200, "[[\"gls\",[\"x\",105]]]")
                : new HttpReply(200, string.Empty));

        var result = await new GoogleProbe(transport, Timeout).ProbeAsync("neo", CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public async Task LookupEchoingAddressIsTaken()
    {
        var transport = new FakeTransport(request =>
            request.Url.Contains("signin/sl/lookup", StringComparison.Ordinal)
                ? new HttpReply(200, "[[\"neo@gmail.com\"]]")
                : new HttpReply(200, string.Empty));

        var result = await new GoogleProbe(transport, Timeout).ProbeAsync("neo", CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
    }

    [Fact]
    public async Task SilentServicesStayUnconfirmed()
    {
        var transport = new FakeTransport(_ => new HttpReply(500, string.Empty));

        var result = await new GoogleProbe(transport, Timeout).ProbeAsync("neo", CancellationToken.None);

        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
    }
}

public class OutlookProbeTests
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [Fact]
    public async Task CredentialTypeZeroIsTakenWithoutSignupRequests()
    {
        var transport = new FakeTransport(_ => new HttpReply(200, "{\"IfExistsResult\":0}"));

        var result = await OutlookProbe.ProbeAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Single(transport.Requests);
    }

    [Fact]
    public async Task SignupFormAvailabilityIsFree()
    {
        var transport = new FakeTransport(request =>
        {
            if (request.Url.Contains("GetCredentialType", StringComparison.Ordinal))
            {
                return new HttpReply(200, "{\"IfExistsResult\":1}");
            }
            if (request.Url.Contains("CheckAvailableSigninNames", StringComparison.Ordinal))
            {
                return new HttpReply(200, "{\"isAvailable\":true}");
            }
            return new HttpReply(200, "<script>var t0 = {\"apiCanary\":\"abc\"};</script>");
        });

        var result = await OutlookProbe.ProbeAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public async Task MissingCanaryIsNetworkErrorWithNote()
    {
        var transport = new FakeTransport(request =>
            request.Url.Contains("GetCredentialType", StringComparison.Ordinal)
                ? new HttpReply(500, string.Empty)
                : new HttpReply(200, "<html></html>"));

        var result = await OutlookProbe.ProbeAsync(transport, "neo", Timeout, CancellationToken.None);

        Assert.Equal(CheckStatus.NetworkError, result.Status);
        Assert.Contains("canary", result.Reason);
    }
}
