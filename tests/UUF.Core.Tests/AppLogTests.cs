using UUF.Core.Diagnostics;
using Xunit;

namespace UUF.Core.Tests;

public class AppLogTests
{
    private static string NewTempFile(out string directory)
    {
        directory = Path.Combine(Path.GetTempPath(), "uuf-log-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, AppLog.FileName);
    }

    [Fact]
    public void ErrorsAreMarkedAndWrittenToFile()
    {
        var path = NewTempFile(out var directory);
        try
        {
            var log = new AppLog(path);
            log.Info("Проверка запущена");
            log.Error("Сеть недоступна");

            var lines = File.ReadAllLines(path);
            Assert.Equal(2, lines.Length);
            Assert.Matches(@"^\[\d\d:\d\d:\d\d\] Проверка запущена$", lines[0]);
            Assert.Matches(@"^\[\d\d:\d\d:\d\d\] ОШИБКА: Сеть недоступна$", lines[1]);

            Assert.Equal(LogLevel.Error, log.Entries[1].Level);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void EntryAddedFiresForEachMessage()
    {
        var path = NewTempFile(out var directory);
        try
        {
            var log = new AppLog(path);
            var seen = new List<LogEntry>();
            log.EntryAdded += seen.Add;

            log.Info("a");
            log.Error("b");

            Assert.Equal(2, seen.Count);
            Assert.Equal("b", seen[1].Message.Replace("ОШИБКА: ", string.Empty));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void MemoryKeepsOnlyLatestEntries()
    {
        var path = NewTempFile(out var directory);
        try
        {
            var log = new AppLog(path, capacity: 3);
            for (var i = 1; i <= 5; i++)
            {
                log.Info("m" + i);
            }

            Assert.Equal(new[] { "m3", "m4", "m5" }, log.Entries.Select(e => e.Message));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void RotatesFileOverLimitToOldLog()
    {
        var path = NewTempFile(out var directory);
        try
        {
            File.WriteAllText(path, new string('x', 2000));
            var log = new AppLog(path, maxBytes: 1000);

            log.RotateIfNeeded();

            Assert.False(File.Exists(path));
            Assert.True(File.Exists(Path.Combine(directory, AppLog.RotatedFileName)));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void SmallFileIsNotRotated()
    {
        var path = NewTempFile(out var directory);
        try
        {
            File.WriteAllText(path, "small");
            new AppLog(path, maxBytes: 1000).RotateIfNeeded();
            Assert.True(File.Exists(path));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
