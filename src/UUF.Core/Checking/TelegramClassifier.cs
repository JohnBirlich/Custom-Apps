using System.Text.RegularExpressions;

namespace UUF.Core.Checking;

public enum TelegramMirrorKind
{
    Free,
    Taken,
    NoProfile,
    Blocked,
    Unreachable,
    Other,
}

public sealed record TelegramMirrorVerdict(TelegramMirrorKind Kind, string Note, string Reason);

public static class TelegramClassifier
{
    private static readonly Regex BlockedPage = new(
        @"доступ к странице ограничен|access is restricted|reestr|roskomnadzor",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static readonly Regex ProfileTitle = new(
        @"class=""tgme_page_title""[^>]*>\s*(<span[^>]*>\s*)?[^<\s]",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static readonly Regex ChannelCounters = new(
        @"class=""tgme_page_extra""[^<]*(subscribers|members|monthly listeners|online)",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static readonly Regex ReservedPage = new(
        @"username has been reserved|reserved for payment|this username is reserved|has been frozen",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static readonly Regex FreePage = new(
        @"if you have (a )?telegram( account|,)|reserve this username|doesn.t seem to exist|username not found|tgme_page_error",
        RegexOptions.IgnoreCase | RegexOptions.Singleline);

    public static TelegramMirrorVerdict ClassifyMirror(HttpReply reply, string mirrorName, string name)
    {
        if (BlockedPage.IsMatch(reply.Content))
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.Blocked,
                mirrorName + " блокируется провайдером — задай «Прокси» над таблицей или включи VPN", string.Empty);
        }

        if (reply.Code == 404)
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.Free, string.Empty,
                "Telegram: " + mirrorName + " вернул 404 — страница @" + name + " никем не занята");
        }

        if (reply.Code == 200 && ReservedPage.IsMatch(reply.Content))
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.Taken, string.Empty,
                "Telegram: тег @" + name + " зарезервирован платформой (резерв или платный ник) — регистрация закрыта");
        }

        if (reply.Code == 200 && (ProfileTitle.IsMatch(reply.Content) || ChannelCounters.IsMatch(reply.Content)))
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.Taken, string.Empty,
                "Telegram: " + mirrorName + " отдаёт публичную страницу профиля или канала @" + name);
        }

        if (reply.Code == 200 && FreePage.IsMatch(reply.Content))
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.Free, string.Empty,
                "Telegram: страница @" + name + " на " + mirrorName + " без профиля и предлагает открыть чат — тег свободен");
        }

        if (reply.Code == 200)
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.NoProfile,
                mirrorName + " ответил без распознаваемых маркеров профиля", string.Empty);
        }

        if (reply.Code == 0)
        {
            return new TelegramMirrorVerdict(TelegramMirrorKind.Unreachable,
                mirrorName + " недоступен: соединение не установлено (сетевая блокировка) — поставь «Прокси» над таблицей или включи VPN",
                string.Empty);
        }

        return new TelegramMirrorVerdict(TelegramMirrorKind.Other,
            mirrorName + " ответил HTTP " + reply.Code + " без распознаваемого результата", string.Empty);
    }

    public static ProbeResult Resolve(string name, IEnumerable<TelegramMirrorVerdict> verdicts)
    {
        bool noProfileSeen = false;
        string lastNote = string.Empty;

        foreach (var verdict in verdicts)
        {
            switch (verdict.Kind)
            {
                case TelegramMirrorKind.Free:
                    return new ProbeResult(CheckStatus.Free, verdict.Reason);
                case TelegramMirrorKind.Taken:
                    return new ProbeResult(CheckStatus.Taken, verdict.Reason);
                case TelegramMirrorKind.NoProfile:
                    noProfileSeen = true;
                    lastNote = verdict.Note;
                    break;
                default:
                    lastNote = verdict.Note;
                    break;
            }
        }

        if (noProfileSeen)
        {
            return new ProbeResult(CheckStatus.Free,
                "Telegram: страница @" + name + " открылась без профиля и без признаков занятости — тег свободен");
        }

        return new ProbeResult(CheckStatus.Unconfirmed,
            "Telegram: " + lastNote + "; попробуй повторить или задать прокси");
    }
}
