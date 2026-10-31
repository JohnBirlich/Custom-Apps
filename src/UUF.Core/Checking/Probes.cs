using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using UUF.Core.Platforms;
using UUF.Core.Transport;

namespace UUF.Core.Checking;

public delegate Task<ProbeResult> NameProbe(string name, CancellationToken cancellationToken);

public static class Probes
{
    public const string BrowserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";

    private const string BrowserAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8";

    private static readonly ProbeResult UnknownNetworkStatus = new(CheckStatus.NetworkError, "Не удалось определить статус");

    public static NameProbe For(string platform, IHttpTransport transport, TimeSpan timeout)
    {
        return platform switch
        {
            PlatformCatalog.Roblox => (name, ct) => ProbeRobloxAsync(transport, name, timeout, ct),
            PlatformCatalog.Steam => (name, ct) => ProbeSteamAsync(transport, name, timeout, ct),
            PlatformCatalog.Telegram => (name, ct) => ProbeTelegramAsync(transport, name, timeout, ct),
            PlatformCatalog.Discord => (name, ct) => ProbeDiscordAsync(transport, name, timeout, ct),
            PlatformCatalog.VK => (name, ct) => ProbeVkAsync(transport, name, timeout, ct),
            PlatformCatalog.MailRu => (name, ct) => ProbeMailRuAsync(transport, name, timeout, ct),
            PlatformCatalog.GitHub => (name, ct) => ProbeGitHubAsync(transport, name, timeout, ct),
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

    public static async Task<ProbeResult> ProbeDiscordAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["username"] = name.ToLowerInvariant(),
        });
        var reply = await transport.SendAsync(new HttpRequestSpec(
            "https://discord.com/api/v9/unique-username/username-attempt-unauthed",
            HttpMethod.Post,
            new Dictionary<string, string>
            {
                ["User-Agent"] = BrowserUserAgent,
                ["Accept"] = "application/json",
                ["Content-Type"] = "application/json",
                ["Origin"] = "https://discord.com",
                ["Referer"] = "https://discord.com/register",
            },
            body,
            "application/json",
            timeout), ct);

        return ClassifyDiscord(reply);
    }

    public static async Task<ProbeResult> ProbeVkAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var api = await transport.SendAsync(new HttpRequestSpec(
            "https://api.vk.com/method/utils.resolveScreenName?screen_name=" + Uri.EscapeDataString(name) + "&v=5.199",
            HttpMethod.Get,
            new Dictionary<string, string>
            {
                ["User-Agent"] = BrowserUserAgent,
                ["Accept"] = "application/json",
            },
            null,
            "application/json",
            timeout), ct);

        if (api.Code != 200)
        {
            return UnknownNetworkStatus;
        }

        if (ParseObject(api.Content) is not JsonObject response)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "VK вернул непонятный ответ на resolveScreenName");
        }

        if (response.TryGetPropertyValue("response", out var resolved))
        {
            if (resolved is JsonObject found && found["object_id"] is JsonNode objectId && IsTruthy(objectId))
            {
                return new ProbeResult(CheckStatus.Taken, "VK разрешил screen name в существующий профиль");
            }
            if (resolved is null)
            {
                return new ProbeResult(CheckStatus.Free,
                    "VK не разрешил screen name в публичный профиль — имя не занято (зарезервированные исключения покажет регистрация)");
            }
        }

        var profile = await transport.SendAsync(new HttpRequestSpec(
            "https://vk.com/" + Uri.EscapeDataString(name),
            HttpMethod.Get,
            BrowserHeaders(),
            null,
            "text/html",
            timeout), ct);

        var escapedName = Regex.Escape(name);
        if (Regex.IsMatch(profile.Content,
                @"id=""profile_short""|id=""profile_full""|""screen_name""\s*:\s*""" + escapedName + @"""",
                RegexOptions.IgnoreCase | RegexOptions.Singleline))
        {
            return new ProbeResult(CheckStatus.Taken, "Публичный профиль VK найден");
        }

        if (profile.Code == 404 || Regex.IsMatch(profile.Content,
                "страница удалена|пользователь не найден|page not found|profile is unavailable",
                RegexOptions.IgnoreCase | RegexOptions.Singleline))
        {
            return new ProbeResult(CheckStatus.Free, "VK не нашёл публичный профиль с таким screen name");
        }

        return new ProbeResult(CheckStatus.Unconfirmed, "VK не раскрыл однозначный статус screen name");
    }

    public static async Task<ProbeResult> ProbeMailRuAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var reply = await transport.SendAsync(new HttpRequestSpec(
            "https://account.mail.ru/api/v1/user/exists?email=" + Uri.EscapeDataString(name + "@mail.ru"),
            HttpMethod.Get,
            new Dictionary<string, string>
            {
                ["User-Agent"] = BrowserUserAgent,
                ["Accept"] = "application/json",
                ["Referer"] = "https://account.mail.ru/signup",
            },
            null,
            "application/json",
            timeout), ct);

        if (reply.Code != 200)
        {
            return UnknownNetworkStatus;
        }

        if (ParseObject(reply.Content) is not JsonObject root)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "Mail.ru вернул неожиданный формат ответа");
        }

        var existsNode = (root["body"] as JsonObject)?["exists"] ?? root["exists"];
        if (existsNode is null)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "Mail.ru вернул неожиданный формат ответа");
        }

        return IsTruthy(existsNode)
            ? new ProbeResult(CheckStatus.Taken, "Mail.ru подтвердил существование адреса")
            : new ProbeResult(CheckStatus.Free, "Mail.ru сообщил, что адрес не занят");
    }

    public static async Task<ProbeResult> ProbeGitHubAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        const string signupUrl = "https://github.com/signup?source=form-home-signup";
        await transport.SendAsync(new HttpRequestSpec(
            signupUrl,
            HttpMethod.Get,
            new Dictionary<string, string>
            {
                ["User-Agent"] = BrowserUserAgent,
                ["Accept"] = "text/html,application/xhtml+xml",
            },
            null,
            "text/html",
            timeout), ct);

        var check = await transport.SendAsync(new HttpRequestSpec(
            "https://github.com/signup_check/username?value=" + Uri.EscapeDataString(name),
            HttpMethod.Get,
            new Dictionary<string, string>
            {
                ["User-Agent"] = BrowserUserAgent,
                ["Accept"] = "*/*",
                ["X-Requested-With"] = "XMLHttpRequest",
                ["Referer"] = signupUrl,
            },
            null,
            "text/plain",
            timeout), ct);

        var signup = ClassifyGitHubSignup(check);
        if (signup is not null)
        {
            return signup;
        }

        var api = await transport.SendAsync(new HttpRequestSpec(
            "https://api.github.com/users/" + Uri.EscapeDataString(name),
            HttpMethod.Get,
            new Dictionary<string, string>
            {
                ["User-Agent"] = "UniversalUsernameFinder",
                ["Accept"] = "application/vnd.github+json",
                ["X-GitHub-Api-Version"] = "2026-03-10",
            },
            null,
            "application/json",
            timeout), ct);

        return ClassifyGitHubApi(api);
    }

    public static ProbeResult? ClassifyGitHubSignup(HttpReply reply)
    {
        var body = reply.Content.Trim();
        if (reply.Code == 200 && (body.Length == 0 || Regex.IsMatch(body, @"^(available|true|username is available)\.?$", RegexOptions.IgnoreCase)))
        {
            return new ProbeResult(CheckStatus.Free, "Регистрационный endpoint GitHub не сообщил о занятости имени");
        }

        if ((reply.Code == 403 || reply.Code == 422)
            && Regex.IsMatch(body, "already taken|reserved word|username is taken|not available|unavailable", RegexOptions.IgnoreCase))
        {
            return Regex.IsMatch(body, "reserved word|invalid", RegexOptions.IgnoreCase)
                ? new ProbeResult(CheckStatus.Invalid, "GitHub отклонил имя как зарезервированное или недопустимое")
                : new ProbeResult(CheckStatus.Taken, "Регистрационный endpoint GitHub сообщил, что имя занято");
        }

        return null;
    }

    public static ProbeResult ClassifyGitHubApi(HttpReply reply)
    {
        return reply.Code switch
        {
            200 => new ProbeResult(CheckStatus.Taken, "Публичный профиль GitHub найден"),
            404 => new ProbeResult(CheckStatus.Free, "GitHub: профиль с таким именем не найден"),
            403 => new ProbeResult(CheckStatus.NetworkError, "GitHub ограничил анонимный API (403/возможный лимит)"),
            _ => new ProbeResult(CheckStatus.Unconfirmed, "GitHub не дал однозначного ответа (HTTP " + reply.Code + ")"),
        };
    }

    public static ProbeResult ClassifyDiscord(HttpReply reply)
    {
        if (reply.Code == 200)
        {
            if (ParseObject(reply.Content) is not JsonObject response)
            {
                return new ProbeResult(CheckStatus.Unconfirmed, "Discord не вернул признак занятости имени");
            }

            var taken = response["taken"] ?? response["username_taken"];
            if (taken is not null)
            {
                var kind = taken.GetValueKind();
                if (kind == JsonValueKind.True) return new ProbeResult(CheckStatus.Taken, "Discord сообщил, что имя занято");
                if (kind == JsonValueKind.False) return new ProbeResult(CheckStatus.Free, "Discord вернул taken=false для username");
                return new ProbeResult(CheckStatus.Unconfirmed, "Discord вернул признак занятости в неожиданном виде");
            }

            var message = response["message"]?.ToString() ?? string.Empty;
            if (Regex.IsMatch(message, "already taken|username is taken", RegexOptions.IgnoreCase))
            {
                return new ProbeResult(CheckStatus.Taken, "Discord сообщил, что имя занято");
            }

            return new ProbeResult(CheckStatus.Unconfirmed, "Discord не вернул признак занятости имени");
        }

        if (reply.Code == 400 || reply.Code == 422)
        {
            return new ProbeResult(CheckStatus.Invalid, "Discord отклонил формат имени");
        }

        return UnknownNetworkStatus;
    }

    private static JsonObject? ParseObject(string content)
    {
        try
        {
            return JsonNode.Parse(content) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static bool IsTruthy(JsonNode node)
    {
        return node.GetValueKind() switch
        {
            JsonValueKind.True => true,
            JsonValueKind.Number => node.GetValue<double>() != 0,
            JsonValueKind.String => !string.IsNullOrEmpty(node.GetValue<string>()),
            _ => false,
        };
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
