using System.Net;
using System.Net.Http;
using System.Text;
using UUF.Core.Checking;

namespace UUF.Core.Transport;

public sealed class HttpTransport : IHttpTransport, IDisposable
{
    private const int MaxRedirects = 5;
    private readonly HttpClient _client;

    public HttpTransport(HttpMessageHandler handler)
    {
        _client = new HttpClient(handler, disposeHandler: true);
    }

    public static HttpTransport Create(string? proxyUrl)
    {
        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            UseCookies = true,
            CookieContainer = new CookieContainer(),
        };
        if (!string.IsNullOrWhiteSpace(proxyUrl))
        {
            handler.UseProxy = true;
            handler.Proxy = new WebProxy(proxyUrl.Trim());
        }
        return new HttpTransport(handler);
    }

    public async Task<HttpReply> SendAsync(HttpRequestSpec request, CancellationToken cancellationToken)
    {
        var url = request.Url;
        var method = request.Method;
        var body = request.Body;

        for (var redirects = 0; ; redirects++)
        {
            HttpReply? reply = null;
            try
            {
                using var message = new HttpRequestMessage(method, url);
                foreach (var header in request.Headers)
                {
                    message.Headers.TryAddWithoutValidation(header.Key, header.Value);
                }
                if (body is not null && method != HttpMethod.Get && method != HttpMethod.Head)
                {
                    message.Content = new StringContent(body, Encoding.UTF8, request.ContentType);
                }

                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(request.Timeout);

                using var response = await _client.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
                var code = (int)response.StatusCode;
                var headers = CollectHeaders(response);

                if (code is >= 300 and < 400 && redirects < MaxRedirects && response.Headers.Location is not null)
                {
                    url = new Uri(new Uri(url), response.Headers.Location).AbsoluteUri;
                    if (code is 301 or 302 or 303 && method != HttpMethod.Get && method != HttpMethod.Head)
                    {
                        method = HttpMethod.Get;
                        body = null;
                    }
                    continue;
                }

                var content = await response.Content.ReadAsStringAsync(timeout.Token);
                reply = new HttpReply(code, content, headers);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                reply = new HttpReply(0, string.Empty);
            }
            catch (HttpRequestException)
            {
                reply = new HttpReply(0, string.Empty);
            }
            catch (IOException)
            {
                reply = new HttpReply(0, string.Empty);
            }

            if (reply is not null)
            {
                return reply;
            }
        }
    }

    public void Dispose()
    {
        _client.Dispose();
    }

    private static IReadOnlyDictionary<string, string> CollectHeaders(HttpResponseMessage response)
    {
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var header in response.Headers)
        {
            headers[header.Key] = string.Join(",", header.Value);
        }
        return headers;
    }
}
