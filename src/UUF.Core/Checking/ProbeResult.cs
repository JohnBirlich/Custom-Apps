namespace UUF.Core.Checking;

public sealed record ProbeResult(CheckStatus Status, string Reason);

public sealed record HttpReply(int Code, string Content);
