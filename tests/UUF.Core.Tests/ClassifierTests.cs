using UUF.Core.Checking;
using Xunit;

namespace UUF.Core.Tests;

public class RobloxClassifierTests
{
    [Theory]
    [InlineData(0, CheckStatus.Free)]
    [InlineData(1, CheckStatus.Taken)]
    [InlineData(2, CheckStatus.Invalid)]
    [InlineData(3, CheckStatus.Invalid)]
    [InlineData(10, CheckStatus.Invalid)]
    [InlineData(7, CheckStatus.Unconfirmed)]
    public void MapsValidatorCodes(int code, CheckStatus expected)
    {
        var result = RobloxClassifier.Classify(new HttpReply(200, "{\"code\":" + code + ",\"message\":\"\"}"));
        Assert.Equal(expected, result.Status);
    }

    [Fact]
    public void BrokenBodyIsUnconfirmed()
    {
        Assert.Equal(CheckStatus.Unconfirmed, RobloxClassifier.Classify(new HttpReply(200, "не json")).Status);
        Assert.Equal(CheckStatus.Unconfirmed, RobloxClassifier.Classify(new HttpReply(200, "{\"message\":\"x\"}")).Status);
    }

    [Fact]
    public void Forbidden_IsUnconfirmedAndDoesNotPretendToBeFree()
    {
        var result = RobloxClassifier.Classify(new HttpReply(403, string.Empty));
        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
    }

    [Theory]
    [InlineData(500)]
    [InlineData(429)]
    public void ServerErrorsAreUnconfirmed(int code)
    {
        Assert.Equal(CheckStatus.Unconfirmed, RobloxClassifier.Classify(new HttpReply(code, string.Empty)).Status);
    }

    [Fact]
    public void NoResponseIsNetworkError()
    {
        Assert.Equal(CheckStatus.NetworkError, RobloxClassifier.Classify(new HttpReply(0, string.Empty)).Status);
    }
}

public class SteamClassifierTests
{
    [Fact]
    public void ProfilePageIsTakenWithName()
    {
        const string html = "<title>Steam Community :: Vasya &amp; Co</title><div class=\"profile_header\"></div>";
        var result = SteamClassifier.Classify(new HttpReply(200, html));
        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Equal("Профиль сообщества занят: Vasya & Co", result.Reason);
    }

    [Fact]
    public void NotFoundIsFree()
    {
        var result = SteamClassifier.Classify(new HttpReply(404, "<title>Steam Community :: Error</title>"));
        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public void ErrorTextOnPageIsFreeEvenWith200()
    {
        var result = SteamClassifier.Classify(new HttpReply(200, "The specified profile could not be found."));
        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public void UnknownPageIsUnconfirmed()
    {
        Assert.Equal(CheckStatus.Unconfirmed, SteamClassifier.Classify(new HttpReply(200, "<html></html>")).Status);
    }
}

public class TelegramClassifierTests
{
    private const string Name = "alexcat";

    private static TelegramMirrorVerdict Mirror(int code, string content = "", string mirror = "t.me")
    {
        return TelegramClassifier.ClassifyMirror(new HttpReply(code, content), mirror, Name);
    }

    [Fact]
    public void NotFoundOnTmeIsFree()
    {
        var result = TelegramClassifier.Resolve(Name, new[] { Mirror(404) });
        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public void PageWithoutProfileIsFreeNotUnconfirmed()
    {
        var result = TelegramClassifier.Resolve(Name, new[] { Mirror(200, "<html>nothing</html>") });
        Assert.Equal(CheckStatus.Free, result.Status);
        Assert.Contains("без профиля", result.Reason);
    }

    [Fact]
    public void PageWithProfileTitleIsTaken()
    {
        const string html = "<div class=\"tgme_page_title\"><span>Alex</span></div>";
        var result = TelegramClassifier.Resolve(Name, new[] { Mirror(200, html) });
        Assert.Equal(CheckStatus.Taken, result.Status);
    }

    [Fact]
    public void ReservedUsernameIsTaken()
    {
        var result = TelegramClassifier.Resolve(Name, new[] { Mirror(200, "This username is reserved") });
        Assert.Equal(CheckStatus.Taken, result.Status);
        Assert.Contains("зарезервирован", result.Reason);
    }

    [Fact]
    public void BlockedMirrorIsSkippedAndNextMirrorDecides()
    {
        var verdicts = new[]
        {
            Mirror(200, "доступ к странице ограничен", "t.me"),
            Mirror(404, string.Empty, "telegram.dog"),
        };
        var result = TelegramClassifier.Resolve(Name, verdicts);
        Assert.Equal(CheckStatus.Free, result.Status);
    }

    [Fact]
    public void AllMirrorsUnreachableIsUnconfirmedWithProxyHint()
    {
        var verdicts = new[] { Mirror(0), Mirror(0, string.Empty, "telegram.me") };
        var result = TelegramClassifier.Resolve(Name, verdicts);
        Assert.Equal(CheckStatus.Unconfirmed, result.Status);
        Assert.Contains("Прокси", result.Reason);
    }

    [Fact]
    public void TakenOnOneMirrorStopsTheSearch()
    {
        var verdicts = new[]
        {
            Mirror(200, "<div class=\"tgme_page_title\"><span>Alex</span></div>", "t.me"),
            Mirror(404, string.Empty, "telegram.dog"),
        };
        Assert.Equal(CheckStatus.Taken, TelegramClassifier.Resolve(Name, verdicts).Status);
    }
}
