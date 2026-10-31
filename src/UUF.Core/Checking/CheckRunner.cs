namespace UUF.Core.Checking;

public sealed record CheckJob(string Name, string Platform);

public sealed class PauseController
{
    private readonly object _sync = new();
    private TaskCompletionSource<bool> _gate = CreateOpenGate();

    public bool IsPaused
    {
        get
        {
            lock (_sync)
            {
                return !_gate.Task.IsCompleted;
            }
        }
    }

    public void Pause()
    {
        lock (_sync)
        {
            if (_gate.Task.IsCompleted)
            {
                _gate = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            }
        }
    }

    public void Resume()
    {
        lock (_sync)
        {
            _gate.TrySetResult(true);
        }
    }

    public Task WaitIfPausedAsync(CancellationToken cancellationToken)
    {
        Task gate;
        lock (_sync)
        {
            gate = _gate.Task;
        }
        return gate.WaitAsync(cancellationToken);
    }

    private static TaskCompletionSource<bool> CreateOpenGate()
    {
        var gate = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        gate.SetResult(true);
        return gate;
    }
}

public sealed class CheckRunner
{
    public const int MinThreads = 1;
    public const int MaxThreads = 8;

    private readonly int _threads;

    public CheckRunner(int threads)
    {
        _threads = Math.Clamp(threads, MinThreads, MaxThreads);
    }

    public int Threads => _threads;

    public async Task RunAsync(
        IEnumerable<CheckJob> jobs,
        Func<CheckJob, NameProbe> probeFor,
        PauseController pause,
        Action<CheckJob, ProbeResult> onResult,
        CancellationToken cancellationToken)
    {
        using var slots = new SemaphoreSlim(_threads, _threads);
        var tasks = jobs.Select(job => RunJobAsync(job, probeFor, slots, pause, onResult, cancellationToken)).ToArray();

        try
        {
            await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    private static async Task RunJobAsync(
        CheckJob job,
        Func<CheckJob, NameProbe> probeFor,
        SemaphoreSlim slots,
        PauseController pause,
        Action<CheckJob, ProbeResult> onResult,
        CancellationToken cancellationToken)
    {
        await slots.WaitAsync(cancellationToken);
        try
        {
            await pause.WaitIfPausedAsync(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            ProbeResult result;
            try
            {
                result = await probeFor(job)(job.Name, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                result = new ProbeResult(CheckStatus.NetworkError, exception.Message);
            }

            onResult(job, result);
        }
        finally
        {
            slots.Release();
        }
    }
}
