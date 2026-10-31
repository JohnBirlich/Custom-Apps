using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using UUF.Core.Transport;

namespace UUF.Core.Checking;

public sealed class GoogleProbe
{
    private const string SignupPageUrl = "https://accounts.google.com/signup/v2/webcreateaccount?service=mail&flowEntry=SignUp";
    private const string SignupFormReferer = "https://accounts.google.com/signup/v2/webcreateaccount?service=mail&flowEntry=SignUp";

    private static readonly string[] SetupUrls =
    {
        SignupPageUrl,
        "https://accounts.google.com/signup?service=mail",
    };

    private readonly IHttpTransport _transport;
    private readonly TimeSpan _timeout;
    private readonly Lazy<Task<string>> _setupToken;

    public GoogleProbe(IHttpTransport transport, TimeSpan timeout)
    {
        _transport = transport;
        _timeout = timeout;
        _setupToken = new Lazy<Task<string>>(() => FetchSetupTokenAsync());
    }

    public async Task<ProbeResult> ProbeAsync(string name, CancellationToken ct)
    {
        var email = name + "@gmail.com";
        var token = await _setupToken.Value;
        var code = string.Empty;
        var httpNote = string.Empty;

        var lookupCells = Enumerable.Repeat("null", 4)
            .Append("\"" + email + "\"")
            .Concat(Enumerable.Repeat("null", 42));
        var lookup = await _transport.SendAsync(new HttpRequestSpec(
            "https://accounts.google.com/_/signin/sl/lookup?hl=en",
            HttpMethod.Post,
            new Dictionary<string, string>
            {
                ["User-Agent"] = Probes.BrowserUserAgent,
                ["Accept"] = "*/*",
                ["X-Same-Domain"] = "1",
                ["Origin"] = "https://accounts.google.com",
                ["Referer"] = "https://accounts.google.com/signin/v2/identifier?service=mail",
            },
            "f.req=[[" + string.Join(",", lookupCells) + "]]",
            "application/x-www-form-urlencoded;charset=UTF-8",
            _timeout), ct);

        if (lookup.Code == 200)
        {
            if (Regex.IsMatch(lookup.Content, @"(?s)[,\[]\s*105\s*[,.\]]"))
            {
                code = "1";
            }
            else if (lookup.Content.Contains(email, StringComparison.OrdinalIgnoreCase)
                || Regex.IsMatch(lookup.Content, "(?i)\"gf\"|\"pr\""))
            {
                code = "2";
            }
        }

        if (code.Length == 0)
        {
            var headers = new Dictionary<string, string>
            {
                ["User-Agent"] = Probes.BrowserUserAgent,
                ["Accept"] = "*/*",
                ["Accept-Language"] = "en-US,en;q=0.9",
                ["Google-Accounts-Xsrf"] = "1",
                ["Origin"] = "https://accounts.google.com",
                ["Referer"] = SignupFormReferer,
            };

            var plainCells = Enumerable.Repeat("null", 8)
                .Append("\"" + email + "\"")
                .Append("null")
                .Append("0")
                .Concat(Enumerable.Repeat("null", 6))
                .Append("[1]");
            var variants = new List<(string Url, string Body)>
            {
                ("https://accounts.google.com/_/signup/webusernameavailability",
                    "f.req=[[" + string.Join(",", plainCells) + "]]"),
            };
            if (token.Length > 0)
            {
                variants.Add(("https://accounts.google.com/_/signup/usernameavailability?hl=en",
                    "f.req=[\"" + token.Replace("\"", string.Empty) + "\",\"\",\"\",\"" + email + "\"]"));
            }

            foreach (var (url, body) in variants)
            {
                var reply = await _transport.SendAsync(new HttpRequestSpec(
                    url,
                    HttpMethod.Post,
                    headers,
                    body,
                    "application/x-www-form-urlencoded; charset=UTF-8",
                    _timeout), ct);

                if (reply.Code == 400)
                {
                    httpNote = "валидатор регистрации ответил 400 (Google закрыл его для автоматических запросов)";
                }
                if (reply.Code == 200)
                {
                    code = ParseAvailability(reply.Content);
                }
                if (code.Length > 0 || reply.Code == 429 || reply.Code >= 500)
                {
                    break;
                }
            }
        }

        if (code == "1")
        {
            return new ProbeResult(CheckStatus.Free, "Google: страница входа не нашла аккаунт с этим адресом");
        }
        if (code == "2")
        {
            return new ProbeResult(CheckStatus.Taken, "Google: адрес Gmail используется");
        }
        if (httpNote.Length > 0)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "Google: " + httpNote + "; lookup тоже молчит — проверьте позже или через «Прокси»");
        }
        return new ProbeResult(CheckStatus.Unconfirmed, "Google не вернул распознаваемого ответа — точную доступность покажет только форма регистрации");
    }

    private async Task<string> FetchSetupTokenAsync()
    {
        foreach (var url in SetupUrls)
        {
            var page = await _transport.SendAsync(new HttpRequestSpec(
                url,
                HttpMethod.Get,
                new Dictionary<string, string>
                {
                    ["User-Agent"] = Probes.BrowserUserAgent,
                    ["Accept"] = Probes.BrowserAccept,
                },
                null,
                "text/html",
                _timeout), CancellationToken.None);

            var token = string.Empty;
            var setup = Regex.Match(page.Content, "data-initial-setup-data=\"([^\"]+)\"");
            if (!setup.Success)
            {
                setup = Regex.Match(page.Content, "data-initial-setup-data='([^']+)'");
            }
            if (setup.Success)
            {
                var parts = WebUtility.HtmlDecode(setup.Groups[1].Value).Split(',');
                if (parts.Length > 13)
                {
                    token = parts[13].Trim();
                }
            }
            if (token.Length == 0)
            {
                var fallback = Regex.Match(page.Content, "(AFoagU[A-Za-z0-9_-]{10,})");
                if (fallback.Success)
                {
                    token = fallback.Groups[1].Value;
                }
            }
            if (token.Length > 0)
            {
                return token;
            }
        }

        return string.Empty;
    }

    private static string ParseAvailability(string content)
    {
        var body = content.Trim();

        var nested = Regex.Match(body, @"\[\[\s*null\s*,\s*\[\s*([12])\s*(?:,|\])", RegexOptions.IgnoreCase);
        if (nested.Success)
        {
            return nested.Groups[1].Value;
        }

        var flat = Regex.Match(body, @"(?s)\[\s*null\s*,\s*([12])\s*(?:,|\])", RegexOptions.IgnoreCase);
        if (flat.Success)
        {
            return flat.Groups[1].Value;
        }

        var flag = Regex.Match(body, "(?i)\"(?:usernameAvailable|available)\"\\s*:\\s*(true|false)");
        if (flag.Success)
        {
            return flag.Groups[1].Value.Equals("true", StringComparison.OrdinalIgnoreCase) ? "1" : "2";
        }

        if (Regex.IsMatch(body, "(?i)IDENTIFIER_EXISTS|username.{0,80}(?:taken|not available)|email.{0,80}already"))
        {
            return "2";
        }

        return string.Empty;
    }
}
