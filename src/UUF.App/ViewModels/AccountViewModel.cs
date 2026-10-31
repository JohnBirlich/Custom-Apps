using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Input;
using UUF.Core.Diagnostics;
using UUF.Core.Platforms;
using UUF.Core.Security;
using UUF.Core.Usernames;
using UUF.Core.Vault;

namespace UUF.App.ViewModels;

public sealed class AccountViewModel : INotifyPropertyChanged
{
    private readonly AccountVault _vault;
    private readonly AppLog _log;
    private string _selectedPlatform = PlatformCatalog.Roblox;
    private string _nick = string.Empty;
    private int _passwordLength = 20;
    private string _password = string.Empty;
    private string _registerStatus = string.Empty;
    private AccountRecord? _selectedRecord;
    private string _vaultStatus = string.Empty;

    public AccountViewModel(AccountVault vault, AppLog log)
    {
        _vault = vault;
        _log = log;
        GenerateCommand = new RelayCommand(_ => Generate(), _ => true);
        SaveCommand = new RelayCommand(_ => Save(), _ => CanSave());
        DeleteCommand = new RelayCommand(_ => Delete(), _ => SelectedRecord is not null);
        ReloadVault();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<string> Platforms => PlatformCatalog.Supported;

    public ObservableCollection<AccountRecord> Records { get; } = new();

    public ICommand GenerateCommand { get; }

    public ICommand SaveCommand { get; }

    public ICommand DeleteCommand { get; }

    public string SelectedPlatform
    {
        get => _selectedPlatform;
        set => SetField(ref _selectedPlatform, value, nameof(SelectedPlatform), nameof(NickLabel));
    }

    public string Nick
    {
        get => _nick;
        set => SetField(ref _nick, value, nameof(Nick));
    }

    public int PasswordLength
    {
        get => _passwordLength;
        set => SetField(ref _passwordLength, Math.Clamp(value, PasswordGenerator.MinLength, PasswordGenerator.MaxLength), nameof(PasswordLength));
    }

    public string Password
    {
        get => _password;
        set => SetField(ref _password, value, nameof(Password));
    }

    public string RegisterStatus
    {
        get => _registerStatus;
        private set => SetField(ref _registerStatus, value, nameof(RegisterStatus));
    }

    public string NickLabel => "Ник на " + SelectedPlatform;

    public string RegistrationAddress => PlatformCatalog.DisplayNick(SelectedPlatform, Nick.Trim());

    public AccountRecord? SelectedRecord
    {
        get => _selectedRecord;
        set
        {
            SetField(ref _selectedRecord, value, nameof(SelectedRecord), nameof(SelectedPassword));
            OnPropertyChanged(nameof(SelectedPassword));
        }
    }

    public string SelectedPassword => SelectedRecord?.Password ?? string.Empty;

    public string VaultStatus
    {
        get => _vaultStatus;
        private set => SetField(ref _vaultStatus, value, nameof(VaultStatus));
    }

    public void Generate()
    {
        Password = PasswordGenerator.Generate(PasswordLength);
        RegisterStatus = "Пароль создан локально и никуда не отправляется.";
    }

    private bool CanSave()
    {
        return UsernameRules.IsValid(Nick.Trim(), SelectedPlatform) && Password.Length > 0;
    }

    private void Save()
    {
        var address = RegistrationAddress;
        var records = _vault.Load().ToList();
        var replaced = records.RemoveAll(record =>
            string.Equals(record.Username, address, StringComparison.OrdinalIgnoreCase));

        records.Add(new AccountRecord(address, Password, SelectedPlatform,
            DateTimeOffset.Now.ToString("o")));
        _vault.Save(records);
        _log.Info((replaced > 0 ? "Запись обновлена: " : "Запись сохранена: ") + address + " (" + SelectedPlatform + ")");

        RegisterStatus = replaced > 0
            ? "Запись для " + address + " обновлена в зашифрованном хранилище."
            : "Данные для " + address + " сохранены в зашифрованном хранилище.";
        ReloadVault();
    }

    private void Delete()
    {
        if (SelectedRecord is null) return;
        var target = SelectedRecord;
        var records = _vault.Load().Where(record =>
            !(record.Username == target.Username && record.CreatedAt == target.CreatedAt)).ToList();
        _vault.Save(records);
        _log.Info("Запись удалена: " + target.Username);
        SelectedRecord = null;
        ReloadVault();
        VaultStatus = "Запись удалена.";
    }

    private void ReloadVault()
    {
        Records.Clear();
        try
        {
            foreach (var record in _vault.Load())
            {
                Records.Add(record);
            }
        }
        catch (Exception exception)
        {
            _log.Error("Не удалось прочитать хранилище: " + exception.Message);
            VaultStatus = "Не удалось прочитать хранилище: " + exception.Message;
            return;
        }
        VaultStatus = Records.Count == 0
            ? "Сохранённых записей пока нет."
            : "Записей в зашифрованном хранилище: " + Records.Count;
    }

    private void SetField<T>(ref T field, T value, params string[] changedProperties)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        foreach (var property in changedProperties)
        {
            OnPropertyChanged(property);
        }
    }

    private void OnPropertyChanged(string name)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
