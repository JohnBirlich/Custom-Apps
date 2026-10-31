using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Input;
using UUF.App.Models;
using UUF.Core.Checking;
using UUF.Core.Platforms;
using UUF.Core.Transport;
using UUF.Core.Usernames;

namespace UUF.App.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(15);

    private readonly SynchronizationContext _ui;
    private readonly PauseController _pause = new();
    private CancellationTokenSource? _cancellation;
    private string _namesText = string.Empty;
    private string _selectedPlatform = PlatformCatalog.Roblox;
    private int _threads = 3;
    private string _proxyUrl = string.Empty;
    private string _summary = "Введите ники и нажмите «Проверить»";
    private bool _isRunning;
    private bool _isPaused;

    public MainViewModel()
    {
        _ui = SynchronizationContext.Current ?? new SynchronizationContext();
        StartCommand = new RelayCommand(_ => _ = StartAsync(), _ => CanStart());
        PauseCommand = new RelayCommand(_ => TogglePause(), _ => IsRunning);
        StopCommand = new RelayCommand(_ => Stop(), _ => IsRunning);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<CheckRow> Rows { get; } = new();

    public IReadOnlyList<string> Platforms => PlatformCatalog.Supported;

    public ICommand StartCommand { get; }

    public ICommand PauseCommand { get; }

    public ICommand StopCommand { get; }

    public string NamesText
    {
        get => _namesText;
        set => SetField(ref _namesText, value, nameof(NamesText));
    }

    public string SelectedPlatform
    {
        get => _selectedPlatform;
        set => SetField(ref _selectedPlatform, value, nameof(SelectedPlatform));
    }

    public int Threads
    {
        get => _threads;
        set => SetField(ref _threads, Math.Clamp(value, CheckRunner.MinThreads, CheckRunner.MaxThreads), nameof(Threads));
    }

    public string ProxyUrl
    {
        get => _proxyUrl;
        set => SetField(ref _proxyUrl, value, nameof(ProxyUrl));
    }

    public string Summary
    {
        get => _summary;
        private set => SetField(ref _summary, value, nameof(Summary));
    }

    public bool IsRunning
    {
        get => _isRunning;
        private set => SetField(ref _isRunning, value, nameof(IsRunning), nameof(PauseButtonText));
    }

    public bool IsPaused
    {
        get => _isPaused;
        private set => SetField(ref _isPaused, value, nameof(IsPaused), nameof(PauseButtonText));
    }

    public string PauseButtonText => IsPaused ? "Продолжить" : "Пауза";

    private bool CanStart()
    {
        return !IsRunning && !string.IsNullOrWhiteSpace(NamesText);
    }

    private async Task StartAsync()
    {
        var platform = SelectedPlatform;
        var names = ParseNames(NamesText);
        Rows.Clear();

        var jobs = new List<CheckJob>();
        var rowsByName = new Dictionary<string, CheckRow>(StringComparer.Ordinal);
        foreach (var name in names)
        {
            var row = new CheckRow(name, platform);
            Rows.Add(row);
            rowsByName[name] = row;

            if (UsernameRules.IsValid(name, platform))
            {
                jobs.Add(new CheckJob(name, platform));
            }
            else
            {
                row.Apply(CheckStatus.Invalid, "Ник не подходит под правила платформы " + platform);
            }
        }

        if (jobs.Count == 0)
        {
            UpdateSummary();
            return;
        }

        var cancellation = new CancellationTokenSource();
        _cancellation = cancellation;
        _pause.Resume();
        IsPaused = false;
        IsRunning = true;
        Summary = "Проверка: 0 из " + jobs.Count;

        try
        {
            using var transport = HttpTransport.Create(ProxyUrl);
            var probe = Probes.For(platform, transport, ProbeTimeout);
            var runner = new CheckRunner(Threads);

            await runner.RunAsync(
                jobs,
                _ => probe,
                _pause,
                (job, result) => _ui.Post(_ => ApplyResult(rowsByName, job, result), null),
                cancellation.Token);
        }
        catch (Exception exception)
        {
            Summary = "Проверка прервана: " + exception.Message;
        }
        finally
        {
            IsRunning = false;
            IsPaused = false;
            _cancellation = null;
            cancellation.Dispose();
            UpdateSummary();
        }
    }

    private void ApplyResult(Dictionary<string, CheckRow> rowsByName, CheckJob job, ProbeResult result)
    {
        if (rowsByName.TryGetValue(job.Name, out var row))
        {
            row.Apply(result.Status, result.Reason);
        }
        UpdateSummary();
    }

    private void TogglePause()
    {
        if (IsPaused)
        {
            _pause.Resume();
            IsPaused = false;
        }
        else
        {
            _pause.Pause();
            IsPaused = true;
        }
        UpdateSummary();
    }

    private void Stop()
    {
        _cancellation?.Cancel();
        _pause.Resume();
    }

    private void UpdateSummary()
    {
        var total = Rows.Count;
        var done = Rows.Count(row => row.Status is not (CheckStatus.Pending or CheckStatus.Checking));
        var free = Rows.Count(row => row.Status == CheckStatus.Free);
        var taken = Rows.Count(row => row.Status == CheckStatus.Taken);
        var invalid = Rows.Count(row => row.Status == CheckStatus.Invalid);
        Summary = $"Всего: {total}   Проверено: {done}   Свободен: {free}   Занят: {taken}   Недопустимый: {invalid}";
    }

    private static IReadOnlyList<string> ParseNames(string text)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>();
        foreach (var part in Regex.Split(text, @"[\s,;]+"))
        {
            if (part.Length == 0) continue;
            if (seen.Add(part)) result.Add(part);
        }
        return result;
    }

    private void SetField<T>(ref T field, T value, params string[] changedProperties)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        foreach (var property in changedProperties)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
        }
    }
}
