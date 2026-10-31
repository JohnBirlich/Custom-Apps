using System.Text;

namespace UUF.Core.Diagnostics;

public enum LogLevel
{
    Info,
    Error,
}

public sealed record LogEntry(DateTimeOffset Time, LogLevel Level, string Message)
{
    public string Line => "[" + Time.ToString("HH:mm:ss") + "] " + Message;
}

public sealed class AppLog
{
    public const string FileName = "UniversalUsernameFinder.log";
    public const string RotatedFileName = "UniversalUsernameFinder.old.log";
    public const long DefaultMaxBytes = 2L * 1024 * 1024;
    public const int DefaultCapacity = 1000;

    private readonly object _sync = new();
    private readonly List<LogEntry> _entries = new();
    private readonly long _maxBytes;
    private readonly int _capacity;

    public AppLog(string path, long maxBytes = DefaultMaxBytes, int capacity = DefaultCapacity)
    {
        Path = path;
        _maxBytes = maxBytes;
        _capacity = Math.Max(1, capacity);
    }

    public event Action<LogEntry>? EntryAdded;

    public string Path { get; }

    public static string DefaultPath()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return System.IO.Path.Combine(local, AppFolderName, FileName);
    }

    private const string AppFolderName = "UniversalUsernameFinder";

    public IReadOnlyList<LogEntry> Entries
    {
        get
        {
            lock (_sync)
            {
                return _entries.ToList();
            }
        }
    }

    public void Info(string message)
    {
        Write(LogLevel.Info, message);
    }

    public void Error(string message)
    {
        Write(LogLevel.Error, "ОШИБКА: " + message);
    }

    public void RotateIfNeeded()
    {
        try
        {
            if (!File.Exists(Path))
            {
                return;
            }
            if (new FileInfo(Path).Length <= _maxBytes)
            {
                return;
            }
            var rotated = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(Path) ?? string.Empty, RotatedFileName);
            File.Move(Path, rotated, overwrite: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private void Write(LogLevel level, string message)
    {
        var entry = new LogEntry(DateTimeOffset.Now, level, message);
        lock (_sync)
        {
            _entries.Add(entry);
            if (_entries.Count > _capacity)
            {
                _entries.RemoveRange(0, _entries.Count - _capacity);
            }
        }

        try
        {
            var directory = System.IO.Path.GetDirectoryName(Path);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }
            File.AppendAllText(Path, entry.Line + Environment.NewLine, Encoding.UTF8);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        EntryAdded?.Invoke(entry);
    }
}
