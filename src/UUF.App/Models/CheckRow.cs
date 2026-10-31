using System.ComponentModel;
using UUF.Core.Checking;

namespace UUF.App.Models;

public sealed class CheckRow : INotifyPropertyChanged
{
    private CheckStatus _status = CheckStatus.Pending;
    private string _reason = string.Empty;

    public CheckRow(string name, string platform)
    {
        Name = name;
        Platform = platform;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Name { get; }

    public string Platform { get; }

    public CheckStatus Status
    {
        get => _status;
        private set
        {
            if (_status == value) return;
            _status = value;
            Notify(nameof(Status), nameof(StatusLabel));
        }
    }

    public string StatusLabel => Status.Label();

    public string Reason
    {
        get => _reason;
        private set
        {
            if (_reason == value) return;
            _reason = value;
            Notify(nameof(Reason));
        }
    }

    public void Apply(CheckStatus status, string reason)
    {
        Status = status;
        Reason = reason;
    }

    private void Notify(params string[] properties)
    {
        foreach (var property in properties)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
        }
    }
}
