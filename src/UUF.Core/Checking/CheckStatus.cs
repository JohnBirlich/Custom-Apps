namespace UUF.Core.Checking;

public enum CheckStatus
{
    Pending,
    Checking,
    Free,
    Taken,
    Invalid,
    Unconfirmed,
    NetworkError,
}

public static class CheckStatusText
{
    public static string Label(this CheckStatus status)
    {
        return status switch
        {
            CheckStatus.Pending => "Ожидает",
            CheckStatus.Checking => "Проверяется",
            CheckStatus.Free => "Свободен",
            CheckStatus.Taken => "Занят",
            CheckStatus.Invalid => "Недопустимый",
            CheckStatus.Unconfirmed => "Не подтверждено",
            CheckStatus.NetworkError => "Ошибка сети",
            _ => status.ToString(),
        };
    }
}
