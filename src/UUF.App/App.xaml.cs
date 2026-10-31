using System.Windows;
using UUF.Core.Diagnostics;

namespace UUF.App;

public partial class App : Application
{
    public static AppLog Log { get; } = CreateLog();

    private static AppLog CreateLog()
    {
        var log = new AppLog(AppLog.DefaultPath());
        log.RotateIfNeeded();
        return log;
    }
}
