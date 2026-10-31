using System.Net;
using System.Net.Http;
using UUF.Core.Transport;
using Xunit;

namespace UUF.Core.Tests;

internal sealed class ScriptedHandler : HttpMessageHandler
{
    private readonly Func<HttpRequestMessage, HttpResponseMessage> _respond;

    public ScriptedHandler(Func<HttpRequestMessage, HttpResponseMessage> respond)
    {
        _respond = respond;
    }

    public List<(string Method, string Url)> Calls { get; } = new();

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Calls.Add((request.Method.Method, request.RequestUri!.AbsoluteUri));
        return Task.FromResult(_respond(request));
    }
}

public class HttpTransportTests
{
    private static HttpRequestSpec Get(string url) =>
        new(url, HttpMethod.Get, new Dictionary<string, string>(), null, "text/html", TimeSpan.FromSeconds(5));

    [Fact]
    public async Task FollowsRelativeRedirectAndReturnsFinalBody()
    {
        var handler = new ScriptedHandler(request =>
        {
            if (request.RequestUri!.AbsolutePath == "/x")
            {
                var redirect = new HttpResponseMessage(HttpStatusCode.Found);
                redirect.Headers.Location = new Uri("/y", UriKind.Relative);
                return redirect;
            }
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("done") };
        });
        using var transport = new HttpTransport(handler);

        var reply = await transport.SendAsync(Get("https://a.test/x"), CancellationToken.None);

        Assert.Equal(200, reply.Code);
        Assert.Equal("done", reply.Content);
        Assert.Equal(new[] { "https://a.test/x", "https://a.test/y" }, handler.Calls.Select(c => c.Url));
    }

    [Fact]
    public async Task PostRedirectedWith302BecomesGet()
    {
        var handler = new ScriptedHandler(request =>
        {
            if (request.Method == HttpMethod.Post)
            {
                var redirect = new HttpResponseMessage(HttpStatusCode.Found);
                redirect.Headers.Location = new Uri("https://a.test/next");
                return redirect;
            }
            return new HttpResponseMessage(HttpStatusCode.OK);
        });
        using var transport = new HttpTransport(handler);
        var post = new HttpRequestSpec("https://a.test/start", HttpMethod.Post,
            new Dictionary<string, string>(), "{}", "application/json", TimeSpan.FromSeconds(5));

        var reply = await transport.SendAsync(post, CancellationToken.None);

        Assert.Equal(200, reply.Code);
        Assert.Equal(("GET", "https://a.test/next"), handler.Calls[1]);
    }

    [Fact]
    public async Task RedirectLoopStopsAfterLimitAndReturnsLastStatus()
    {
        var handler = new ScriptedHandler(_ =>
        {
            var redirect = new HttpResponseMessage(HttpStatusCode.Found);
            redirect.Headers.Location = new Uri("https://a.test/loop");
            return redirect;
        });
        using var transport = new HttpTransport(handler);

        var reply = await transport.SendAsync(Get("https://a.test/loop"), CancellationToken.None);

        Assert.Equal(302, reply.Code);
        Assert.Equal(6, handler.Calls.Count);
    }

    [Fact]
    public async Task TransportFailureBecomesCodeZero()
    {
        var handler = new ScriptedHandler(_ => throw new HttpRequestException("connection refused"));
        using var transport = new HttpTransport(handler);

        var reply = await transport.SendAsync(Get("https://a.test/"), CancellationToken.None);

        Assert.Equal(0, reply.Code);
    }

    [Fact]
    public async Task ResponseHeadersAreCaseInsensitive()
    {
        var handler = new ScriptedHandler(_ =>
        {
            var response = new HttpResponseMessage(HttpStatusCode.Forbidden);
            response.Headers.TryAddWithoutValidation("X-CSRF-Token", "abc");
            return response;
        });
        using var transport = new HttpTransport(handler);

        var reply = await transport.SendAsync(Get("https://a.test/"), CancellationToken.None);

        Assert.True(reply.Headers!.TryGetValue("x-csrf-token", out var token));
        Assert.Equal("abc", token);
    }
}
