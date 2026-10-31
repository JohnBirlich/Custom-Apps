using System.Net.Http;

namespace UUF.Core.Transport;

public sealed record HttpRequestSpec(
    string Url,
    HttpMethod Method,
    IReadOnlyDictionary<string, string> Headers,
    string? Body,
    string ContentType,
    TimeSpan Timeout);

public interface IHttpTransport
{
    Task<UUF.Core.Checking.HttpReply> SendAsync(HttpRequestSpec request, CancellationToken cancellationToken);
}
