using System.Text.RegularExpressions;
using UUF.Core.Platforms;

namespace UUF.Core.Usernames;

public static class UsernameRules
{
    private static readonly Regex RobloxChars = new("^[A-Za-z0-9_]+$");
    private static readonly Regex RobloxAlnum = new("[A-Za-z0-9]");
    private static readonly Regex RobloxEdgeOrDouble = new("^_|_$|__");

    private static readonly Regex GoogleChars = new("^[A-Za-z0-9.]+$");
    private static readonly Regex DotEdgeOrDouble = new(@"(^\.|\.$|\.\.)");

    private static readonly Regex MailRuChars = new("^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]$");
    private static readonly Regex DoubleSeparator = new("[._-]{2}");

    private static readonly Regex VkChars = new("^[A-Za-z0-9._]+$");
    private static readonly Regex VkEdgeOrDouble = new(@"(^[._]|[._]$|\.\.|__)");
    private static readonly Regex AllDigits = new(@"^\d+$");

    private static readonly Regex OutlookChars = new("^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]?$");
    private static readonly Regex OutlookEdgeOrDouble = new("([._-]$|[._-]{2})");

    private static readonly Regex GitHubChars = new("^(?!-)(?!.*--)[A-Za-z0-9-]+(?<!-)$");

    private static readonly Regex DiscordChars = new("^[A-Za-z0-9_.]+$");
    private static readonly string[] DiscordReserved = { "discord", "clyde", "nitro", "here", "everyone", "system" };

    private static readonly Regex YouTubeChars = new("^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$");
    private static readonly Regex DoubleDot = new(@"\.\.");

    private static readonly Regex TelegramChars = new("^[A-Za-z][A-Za-z0-9_]*$");

    private static readonly Regex SteamChars = new("^[A-Za-z0-9][A-Za-z0-9_-]*$");

    private static readonly Regex GenericChars = new("^[A-Za-z0-9_.-]+$");

    public static bool IsValid(string? username, string platform)
    {
        if (string.IsNullOrWhiteSpace(username)) return false;

        var length = username.Length;
        return platform switch
        {
            PlatformCatalog.Roblox => IsRobloxValid(username),
            PlatformCatalog.Google => length >= 6 && length <= 30
                && GoogleChars.IsMatch(username) && !DotEdgeOrDouble.IsMatch(username),
            PlatformCatalog.MailRu => length >= 5 && length <= 31
                && MailRuChars.IsMatch(username) && !DoubleSeparator.IsMatch(username),
            PlatformCatalog.VK => length >= 5 && length <= 32
                && VkChars.IsMatch(username) && !VkEdgeOrDouble.IsMatch(username) && !AllDigits.IsMatch(username),
            PlatformCatalog.Outlook => length >= 3 && length <= 64
                && OutlookChars.IsMatch(username) && !OutlookEdgeOrDouble.IsMatch(username),
            PlatformCatalog.GitHub => length >= 1 && length <= 39 && GitHubChars.IsMatch(username),
            PlatformCatalog.Discord => length >= 2 && length <= 32
                && DiscordChars.IsMatch(username) && !DotEdgeOrDouble.IsMatch(username)
                && !DiscordReserved.Contains(username.ToLowerInvariant(), StringComparer.Ordinal),
            PlatformCatalog.YouTube => length >= 3 && length <= 30
                && YouTubeChars.IsMatch(username) && !DoubleDot.IsMatch(username),
            PlatformCatalog.Telegram => length >= 5 && length <= 32 && TelegramChars.IsMatch(username),
            PlatformCatalog.Steam => length >= 3 && length <= 30 && SteamChars.IsMatch(username),
            _ => length >= 3 && length <= 32 && GenericChars.IsMatch(username),
        };
    }

    private static bool IsRobloxValid(string username)
    {
        return username.Length >= 3 && username.Length <= 20
            && RobloxChars.IsMatch(username)
            && RobloxAlnum.IsMatch(username)
            && !RobloxEdgeOrDouble.IsMatch(username);
    }
}
