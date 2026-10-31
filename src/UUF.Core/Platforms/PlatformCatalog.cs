namespace UUF.Core.Platforms;

public static class PlatformCatalog
{
    public const string Roblox = "Roblox";
    public const string Google = "Google";
    public const string MailRu = "Mail.ru";
    public const string VK = "VK";
    public const string Discord = "Discord";
    public const string Outlook = "Outlook";
    public const string Telegram = "Telegram";
    public const string Steam = "Steam";
    public const string GitHub = "GitHub";
    public const string YouTube = "YouTube";

    public static readonly IReadOnlyList<string> Supported = new[]
    {
        Roblox, Google, MailRu, VK, Discord, Outlook, Telegram, Steam, GitHub, YouTube,
    };

    private static readonly IReadOnlyDictionary<string, string> Domains = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        [Google] = "gmail.com",
        [MailRu] = "mail.ru",
        [Outlook] = "outlook.com",
    };

    public static bool IsSupported(string? platform)
    {
        return !string.IsNullOrWhiteSpace(platform) && Supported.Contains(platform, StringComparer.Ordinal);
    }

    public static string DomainOf(string platform)
    {
        return Domains.TryGetValue(platform, out var domain) ? domain : string.Empty;
    }

    public static string DisplayNick(string platform, string name)
    {
        var domain = DomainOf(platform);
        return domain.Length > 0 ? name + "@" + domain : name;
    }
}
