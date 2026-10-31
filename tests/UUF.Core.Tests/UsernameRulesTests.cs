using UUF.Core.Platforms;
using UUF.Core.Usernames;
using Xunit;

namespace UUF.Core.Tests;

public class UsernameRulesTests
{
    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void EmptyOrWhitespaceIsAlwaysInvalid(string? username)
    {
        Assert.False(UsernameRules.IsValid(username, PlatformCatalog.Roblox));
        Assert.False(UsernameRules.IsValid(username, "Unknown"));
    }

    [Theory]
    [InlineData("abc", true)]
    [InlineData("a_b", true)]
    [InlineData("ab", false)]
    [InlineData("_ab", false)]
    [InlineData("ab_", false)]
    [InlineData("a__b", false)]
    [InlineData("a b", false)]
    [InlineData("___", false)]
    [InlineData("abcdefghijklmnopqrst", true)]
    [InlineData("abcdefghijklmnopqrstu", false)]
    public void Roblox(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.Roblox));
    }

    [Theory]
    [InlineData("abcdef", true)]
    [InlineData("abcde", false)]
    [InlineData("a.b.c.d", true)]
    [InlineData(".abcdef", false)]
    [InlineData("abc..def", false)]
    [InlineData("abc_def", false)]
    public void Google(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.Google));
    }

    [Theory]
    [InlineData("abcde", true)]
    [InlineData("abcd", false)]
    [InlineData("a-b_c", true)]
    [InlineData("a--bcd", false)]
    [InlineData("-abcd", false)]
    public void MailRu(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.MailRu));
    }

    [Theory]
    [InlineData("abcde", true)]
    [InlineData("12345", false)]
    [InlineData("abc__de", false)]
    [InlineData("a.b.c", true)]
    [InlineData("abc.", false)]
    public void VK(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.VK));
    }

    [Theory]
    [InlineData("abc", true)]
    [InlineData("ab", false)]
    [InlineData("a.b", true)]
    [InlineData("a..b", false)]
    [InlineData("a-", false)]
    public void Outlook(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.Outlook));
    }

    [Theory]
    [InlineData("a", true)]
    [InlineData("-a", false)]
    [InlineData("a-", false)]
    [InlineData("a--b", false)]
    [InlineData("abcdefghijklmnopqrstuvwxyzabcdefghijklm", true)]
    [InlineData("abcdefghijklmnopqrstuvwxyzabcdefghijklmn", false)]
    public void GitHub(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.GitHub));
    }

    [Theory]
    [InlineData("ab", true)]
    [InlineData("a", false)]
    [InlineData("a.b", true)]
    [InlineData("a..b", false)]
    [InlineData("a_b", true)]
    [InlineData("discord", false)]
    [InlineData("Clyde", false)]
    [InlineData("everyone", false)]
    public void Discord(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.Discord));
    }

    [Theory]
    [InlineData("abc", true)]
    [InlineData("ab", false)]
    [InlineData("a.b", true)]
    [InlineData("a..b", false)]
    [InlineData(".abc", false)]
    [InlineData("abc-", false)]
    public void YouTube(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.YouTube));
    }

    [Theory]
    [InlineData("abcde", true)]
    [InlineData("abcd", false)]
    [InlineData("1abcd", false)]
    [InlineData("ab_cd", true)]
    [InlineData("ab.cd", false)]
    public void Telegram(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.Telegram));
    }

    [Theory]
    [InlineData("abc", true)]
    [InlineData("_abc", false)]
    [InlineData("ab-c", true)]
    [InlineData("ab.c", false)]
    public void Steam(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, PlatformCatalog.Steam));
    }

    [Theory]
    [InlineData("abc", true)]
    [InlineData("ab.c", true)]
    [InlineData("ab", false)]
    [InlineData("ab c", false)]
    public void UnknownPlatformUsesGenericRule(string username, bool expected)
    {
        Assert.Equal(expected, UsernameRules.IsValid(username, "Unknown"));
    }
}

public class PlatformCatalogTests
{
    [Theory]
    [InlineData(PlatformCatalog.Google, "name", "name@gmail.com")]
    [InlineData(PlatformCatalog.MailRu, "name", "name@mail.ru")]
    [InlineData(PlatformCatalog.Outlook, "name", "name@outlook.com")]
    [InlineData(PlatformCatalog.Steam, "name", "name")]
    [InlineData(PlatformCatalog.Discord, "name", "name")]
    public void DisplayNickAddsDomainOnlyForMailPlatforms(string platform, string name, string expected)
    {
        Assert.Equal(expected, PlatformCatalog.DisplayNick(platform, name));
    }

    [Fact]
    public void SupportedListHasTenPlatforms()
    {
        Assert.Equal(10, PlatformCatalog.Supported.Count);
        Assert.True(PlatformCatalog.IsSupported(PlatformCatalog.YouTube));
        Assert.False(PlatformCatalog.IsSupported("Unknown"));
        Assert.False(PlatformCatalog.IsSupported(null));
    }
}
