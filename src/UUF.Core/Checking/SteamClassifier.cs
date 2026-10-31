using System.Net;
using System.Text.RegularExpressions;

namespace UUF.Core.Checking;

public static class SteamClassifier
{
    private static readonly Regex ProfileMarker = new(
        @"class=""profile_header""|id=""personaName""|profile_rightcolumn|profileHeader",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static readonly Regex ErrorMarker = new(
        @"The specified profile could not be found|Steam Community :: Error",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static readonly Regex TitleName = new(
        @"<title>\s*Steam Community :: (.*?)\s*</title>",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    public static ProbeResult Classify(HttpReply reply)
    {
        bool profileFound = ProfileMarker.IsMatch(reply.Content);
        bool errorFound = reply.Code == 404 || ErrorMarker.IsMatch(reply.Content);

        if (reply.Code == 200 && profileFound && !errorFound)
        {
            var title = TitleName.Match(reply.Content);
            var profileName = title.Success ? WebUtility.HtmlDecode(title.Groups[1].Value).Trim() : string.Empty;
            return new ProbeResult(CheckStatus.Taken, profileName.Length > 0
                ? "Профиль сообщества занят: " + profileName
                : "Профиль сообщества занят");
        }

        if (errorFound)
        {
            return new ProbeResult(CheckStatus.Free, "Адрес steamcommunity.com/id не занят — профиль не найден");
        }

        return new ProbeResult(CheckStatus.Unconfirmed, "Steam не раскрыл статус публичного адреса");
    }
}
