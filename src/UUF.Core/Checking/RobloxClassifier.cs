using System.Text.Json;

namespace UUF.Core.Checking;

public static class RobloxClassifier
{
    public static ProbeResult Classify(HttpReply reply)
    {
        if (reply.Code == 200)
        {
            return ClassifyValidatorBody(reply.Content);
        }

        if (reply.Code == 403)
        {
            return new ProbeResult(CheckStatus.Unconfirmed,
                "Roblox отклонил запрос (403): антибот-защита или CSRF-токен не принят");
        }

        if (reply.Code >= 400)
        {
            return new ProbeResult(CheckStatus.Unconfirmed,
                $"Roblox ответил HTTP {reply.Code} без распознаваемого результата валидации");
        }

        return new ProbeResult(CheckStatus.NetworkError, "Не удалось определить статус");
    }

    private static ProbeResult ClassifyValidatorBody(string content)
    {
        int? code = ReadCode(content);
        if (code is null)
        {
            return new ProbeResult(CheckStatus.Unconfirmed, "Roblox вернул пустой или непонятный ответ.");
        }

        return code.Value switch
        {
            0 => new ProbeResult(CheckStatus.Free, "Регистрационный валидатор Roblox сообщил, что имя доступно"),
            1 => new ProbeResult(CheckStatus.Taken, "Roblox сообщил, что имя уже используется"),
            2 => new ProbeResult(CheckStatus.Invalid, "Roblox отклонил имя фильтром содержания"),
            3 or 10 => new ProbeResult(CheckStatus.Invalid, "Roblox отклонил формат имени"),
            _ => new ProbeResult(CheckStatus.Unconfirmed, "Roblox вернул неизвестный код валидатора: " + code.Value),
        };
    }

    private static int? ReadCode(string content)
    {
        try
        {
            using var document = JsonDocument.Parse(content);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            if (!document.RootElement.TryGetProperty("code", out var codeElement)) return null;
            if (codeElement.ValueKind != JsonValueKind.Number || !codeElement.TryGetInt32(out var value)) return null;
            return value;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
