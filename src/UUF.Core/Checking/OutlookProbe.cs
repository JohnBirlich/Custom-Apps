using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using UUF.Core.Transport;

namespace UUF.Core.Checking;

public static class OutlookProbe
{
    private const string CreateAccountUrl = "https://signup.live.com/CreateAccount?lic=1&uiflvr=1103&scid=200055&signup=1";
    private const string SignupHomeUrl = "https://signup.live.com/?lic=1";
    private const string CheckNameUrl = "https://signup.live.com/API/CheckAvailableSigninNames";

    public static async Task<ProbeResult> ProbeAsync(IHttpTransport transport, string name, TimeSpan timeout, CancellationToken ct)
    {
        var signInName = name + "@outlook.com";

        var credential = await CheckCredentialTypeAsync(transport, signInName, timeout, ct);
        if (credential is not null && credential.Status is CheckStatus.Taken or CheckStatus.Free)
        {
            return credential;
        }

        var status = credential?.Status ?? CheckStatus.NetworkError;
        var reason = credential?.Reason ?? "Не удалось определить статус";
        var note = string.Empty;

        for (var attempt = 1; attempt <= 2; attempt++)
        {
            var canary = await FetchCanaryAsync(transport, timeout, ct);
            if (canary.Length == 0)
            {
                note = "страница регистрации не отдала canary";
                break;
            }

            var uaid = Guid.NewGuid().ToString();
            var payload = new JsonObject
            {
                ["signInName"] = signInName,
                ["includePhone"] = false,
                ["countryCode"] = "RU",
                ["uaid"] = uaid,
                ["uiflvr"] = 1103,
                ["scid"] = 1001,
                ["hpgid"] = 1001,
            }.ToJsonString();

            var reply = await transport.SendAsync(new HttpRequestSpec(
                CheckNameUrl,
                HttpMethod.Post,
                new Dictionary<string, string>
                {
                    ["User-Agent"] = Probes.BrowserUserAgent,
                    ["Accept"] = "application/json",
                    ["canary"] = canary,
                    ["Origin"] = "https://signup.live.com",
                    ["Referer"] = CreateAccountUrl + "&uaid=" + uaid,
                },
                payload,
                "application/json; charset=UTF-8",
                timeout), ct);

            var text = reply.Content;
            var available = Regex.Match(text, "(?i)\"isAvailable\"\\s*:\\s*(true|false)");
            if (reply.Code == 200 && available.Success)
            {
                return available.Groups[1].Value.Equals("true", StringComparison.OrdinalIgnoreCase)
                    ? new ProbeResult(CheckStatus.Free, "Outlook: форма регистрации подтвердила доступность адреса " + signInName)
                    : new ProbeResult(CheckStatus.Taken, "Outlook: форма регистрации отклонила адрес " + signInName + " как недоступный");
            }

            if (Regex.IsMatch(text, "(?i)\"type\"\\s*:\\s*\"MemberNameUnavailable\""))
            {
                return new ProbeResult(CheckStatus.Taken, "Outlook: форма регистрации сообщает, что адрес занят или недоступен");
            }

            if (reply.Code == 400 || Regex.IsMatch(text, "(?i)\"errorDefinitions\""))
            {
                var message = Regex.Match(text, "(?i)\"message\"\\s*:\\s*\"([^\"]+)\"").Groups[1].Value;
                if (Regex.IsMatch(message, "(?i)alread|taken|not available|unavailable|недоступен"))
                {
                    return new ProbeResult(CheckStatus.Taken, "Outlook: форма регистрации сообщает, что адрес занят или недоступен");
                }
                if (Regex.IsMatch(message, "(?i)forbidden|reserved|not allowed|invalid"))
                {
                    return new ProbeResult(CheckStatus.Invalid, "Outlook: форма регистрации отклонила имя как недопустимое или зарезервированное");
                }
                if (message.Length > 0)
                {
                    note = "форма регистрации: " + (message.Length > 120 ? message[..120] : message);
                }
            }

            var exists = Regex.Match(text, "(?i)\"IfExistsResult\"\\s*:\\s*(-?[0-9]+)");
            if (exists.Success)
            {
                var existsCode = int.Parse(exists.Groups[1].Value);
                if (existsCode == 0)
                {
                    return new ProbeResult(CheckStatus.Taken, "Outlook: форма регистрации вернула IfExistsResult=0 — аккаунт существует");
                }
                note = "форма регистрации вернула IfExistsResult=" + existsCode;
            }

            if (reply.Code is 401 or 403 || Regex.IsMatch(text, "(?i)canary|invalid_request"))
            {
                note = "canary устарел или запрос отклонён (HTTP " + reply.Code + "), обновляю страницу";
                if (attempt == 2)
                {
                    break;
                }
                continue;
            }

            if (note.Length == 0)
            {
                var preview = Regex.Replace(text, @"\s+", " ").Trim();
                if (preview.Length > 90)
                {
                    preview = preview[..90];
                }
                note = preview.StartsWith('<')
                    ? "форма регистрации отдала HTML вместо JSON (включилась защита Microsoft) — повтори позже или задай «Прокси»"
                    : "ответ формы регистрации непонятен (HTTP " + reply.Code + "): " + preview;
            }
        }

        if (note.Length > 0)
        {
            reason = "Outlook: " + note + " — точный ответ даёт только форма регистрации, статус не подтверждён";
        }

        return new ProbeResult(status, reason);
    }

    private static async Task<ProbeResult?> CheckCredentialTypeAsync(IHttpTransport transport, string signInName, TimeSpan timeout, CancellationToken ct)
    {
        var body = new JsonObject
        {
            ["username"] = signInName,
            ["isOtherIdEntry"] = false,
        }.ToJsonString();

        var reply = await transport.SendAsync(new HttpRequestSpec(
            "https://login.microsoftonline.com/common/GetCredentialType",
            HttpMethod.Post,
            new Dictionary<string, string>
            {
                ["User-Agent"] = Probes.BrowserUserAgent,
                ["Accept"] = "application/json",
                ["Origin"] = "https://login.microsoftonline.com",
                ["Referer"] = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            },
            body,
            "application/json; charset=UTF-8",
            timeout), ct);

        var exists = Regex.Match(reply.Content, "(?i)\"IfExistsResult\"\\s*:\\s*(-?[0-9]+)");
        var errorCode = Regex.Match(reply.Content, "\"code\"\\s*:\\s*([0-9]+)");
        var throttled = errorCode.Success && (int.Parse(errorCode.Groups[1].Value) is 1000 or 1065);

        if (reply.Code == 200 && exists.Success)
        {
            var code = int.Parse(exists.Groups[1].Value);
            return code switch
            {
                0 => new ProbeResult(CheckStatus.Taken, "Outlook: IfExistsResult=0 — Microsoft сообщает, что пользователь с таким адресом существует"),
                1 => new ProbeResult(CheckStatus.Unconfirmed, "Outlook: аккаунта для входа нет (IfExistsResult=1), но форма регистрации может отказать (резерв/ограничения). Ответа signup.live.com не получил — не считаю имя свободным"),
                4 => new ProbeResult(CheckStatus.Unconfirmed, "Outlook: IfExistsResult=4 — федеративный домен, доступность личного адреса не подтверждена"),
                5 or 6 => new ProbeResult(CheckStatus.Unconfirmed, "Outlook: IfExistsResult=" + code + " — домен не найден или ошибка домена"),
                _ => new ProbeResult(CheckStatus.Unconfirmed, "Outlook: неизвестный IfExistsResult=" + code),
            };
        }

        if (throttled)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "Outlook: Microsoft ограничил частоту проверок (код " + errorCode.Groups[1].Value + "); увеличьте паузу");
        }

        if (reply.Code == 200)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "Outlook: GetCredentialType ответил без поля IfExistsResult; включаю резервную проверку регистрации");
        }

        return null;
    }

    private static async Task<string> FetchCanaryAsync(IHttpTransport transport, TimeSpan timeout, CancellationToken ct)
    {
        foreach (var url in new[] { CreateAccountUrl, SignupHomeUrl })
        {
            var page = await transport.SendAsync(new HttpRequestSpec(
                url,
                HttpMethod.Get,
                new Dictionary<string, string>
                {
                    ["User-Agent"] = Probes.BrowserUserAgent,
                    ["Accept"] = Probes.BrowserAccept,
                },
                null,
                "text/html",
                timeout), ct);

            var canary = Regex.Match(page.Content, "(?i)\"apiCanary\"\\s*[:=]\\s*\"([^\"]+)\"");
            if (canary.Success)
            {
                return canary.Groups[1].Value;
            }

            var boot = Regex.Match(page.Content, @"(?s)var\s+t0\s*=\s*(\{.*?\})\s*;");
            if (boot.Success)
            {
                try
                {
                    var value = JsonNode.Parse(boot.Groups[1].Value)?["apiCanary"]?.GetValue<string>();
                    if (!string.IsNullOrWhiteSpace(value))
                    {
                        return value;
                    }
                }
                catch (Exception exception) when (exception is JsonException or InvalidOperationException)
                {
                }
            }
        }

        return string.Empty;
    }
}
