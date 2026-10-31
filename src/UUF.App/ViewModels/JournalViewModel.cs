using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Threading;
using UUF.Core.Diagnostics;

namespace UUF.App.ViewModels;

public sealed class JournalViewModel : INotifyPropertyChanged
{
    private readonly AppLog _log;
    private readonly SynchronizationContext _ui;
    private readonly Action<LogEntry> _entryAdded;
    private bool _onlyErrors;

    public JournalViewModel(AppLog log)
    {
        _log = log;
        _ui = SynchronizationContext.Current ?? new SynchronizationContext();
        _entryAdded = entry => _ui.Post(_ => OnEntryAdded(entry), null);
        _log.EntryAdded += _entryAdded;
        Refresh();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<LogEntry> Visible { get; } = new();

    public bool OnlyErrors
    {
        get => _onlyErrors;
        set
        {
            if (_onlyErrors == value) return;
            _onlyErrors = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(OnlyErrors)));
            Refresh();
        }
    }

    public string LogPath => _log.Path;

    public void Detach()
    {
        _log.EntryAdded -= _entryAdded;
    }

    public void Refresh()
    {
        Visible.Clear();
        foreach (var entry in _log.Entries)
        {
            if (Matches(entry)) Visible.Add(entry);
        }
    }

    private void OnEntryAdded(LogEntry entry)
    {
        if (Matches(entry)) Visible.Add(entry);
    }

    private bool Matches(LogEntry entry)
    {
        return !OnlyErrors || entry.Level == LogLevel.Error;
    }
}
