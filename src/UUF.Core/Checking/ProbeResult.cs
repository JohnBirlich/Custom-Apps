namespace UUF.Core.Checking;

public sealed record ProbeResult(CheckStatus Status, string Reason, bool StopRun = false);

public sealed record HttpReply(int Code, string Content, IReadOnlyDictionary<string, string>? Headers = null);
