using System.Net.Http;
using System.Text.Json;
using UUF.Core.Transport;

namespace UUF.Core.Checking;

public delegate Task<ProbeResult> NameProbe(string name, CancellationToken cancellationToken);

public static class Probes
{
    public const string BrowserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";

    private const string BrowserAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";

    public static NameProbe For(string platform, IHttpTransport transport, TimeSpan timeout)
    {
        return platform switch
        {
            UUF.Core.Platforms.PlatformCatalog.Roblox => (name, ct) => ProbeRobloxAsync(transport, name, timeout, ct),
            UUF.Core.Platforms.PlatformCatalog.Steam => (name, ct) => ProbeSteamAsync(transport, name, timeout, ct),
            UUF.Core.Platforms.PlatformCatalog.Telegram => (name, ct) => ProbeTelegramAsync(transport, name, timeout, ct),
            _ => (_, _) => Task.FromResult(new ProbeResult(CheckStatus.Unconfirmed,
                platform + " пока не перенесена в C#-версию; используйте PowerShell-версию")),
        };
    }

    public static async Task<ProbeResult> ProbeRobloxAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new
        {
            username = name,
            birthday = "2000-01-01T00:00:00.000Z",
            context = "Signup",
        });
        var headers = new Dictionary<string, string>
        {
            ["User-Agent"] = BrowserUserAgent,
            ["Accept"] = "application/json",
            ["Origin"] = "https://www.roblox.com",
            ["Referer"] = "https://www.roblox.com/",
        };

        HttpReply reply;
        var csrfAttempts = 0;
        while (true)
        {
            reply = await transport.SendAsync(new HttpRequestSpec(
                "https://auth.roblox.com/v1/usernames/validate",
                HttpMethod.Post,
                headers,
                body,
                "application/json; charset=UTF-8",
                timeout), ct);

            if (reply.Code == 403 && csrfAttempts < 2
                && reply.Headers is not null
                && reply.Headers.TryGetValue("X-CSRF-Token", out var token)
                && !string.IsNullOrWhiteSpace(token))
            {
                headers["X-CSRF-Token"] = token;
                csrfAttempts++;
                continue;
            }
            break;
        }

        return RobloxClassifier.Classify(reply);
    }

    public static async Task<ProbeResult> ProbeSteamAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var reply = await transport.SendAsync(new HttpRequestSpec(
            "https://steamcommunity.com/id/" + name,
            HttpMethod.Get,
            BrowserHeaders(),
            null,
            "text/html",
            timeout), ct);
        return SteamClassifier.Classify(reply);
    }

    public static async Task<ProbeResult> ProbeTelegramAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var mirrors = new[]
        {
            ("https://t.me/", "t.me"),
            ("https://telegram.dog/", "telegram.dog"),
            ("https://telegram.me/", "telegram.me"),
        };
        var mirrorTimeout = TimeSpan.FromSeconds(Math.Min(timeout.TotalSeconds, 12));

        var verdicts = new List<TelegramMirrorVerdict>();
        foreach (var (baseUrl, mirrorName) in mirrors)
        {
            ct.ThrowIfCancellationRequested();
            var reply = await transport.SendAsync(new HttpRequestSpec(
                baseUrl + Uri.EscapeDataString(name),
                HttpMethod.Get,
                BrowserHeaders(),
                null,
                "text/html",
                mirrorTimeout), ct);

            var verdict = TelegramClassifier.ClassifyMirror(reply, mirrorName, name);
            verdicts.Add(verdict);
            if (verdict.Kind is TelegramMirrorKind.Free or TelegramMirrorKind.Taken)
            {
                break;
            }
        }

        return TelegramClassifier.Resolve(name, verdicts);
    }

    private static Dictionary<string, string> BrowserHeaders()
    {
        return new Dictionary<string, string>
        {
            ["User-Agent"] = BrowserUserAgent,
            ["Accept"] = BrowserAccept,
        };
    }
}
