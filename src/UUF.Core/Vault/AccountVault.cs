using System.Text;
using System.Text.Json;
using UUF.Core.Security;

namespace UUF.Core.Vault;

public sealed record AccountRecord(string Username, string Password, string Platform, string CreatedAt);

public sealed class AccountVault
{
    public const string FileName = "accounts.dat";
    public const string AppFolderName = "UniversalUsernameFinder";
    public const string LegacyFolderName = "RobloxNickFinder";
    public static readonly byte[] Entropy = Encoding.UTF8.GetBytes("RobloxNickFinder:account-vault:v1");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ISecretProtector _protector;
    private readonly string _directory;

    public AccountVault(string directory, ISecretProtector protector)
    {
        _directory = directory;
        _protector = protector;
    }

    public string FilePath => Path.Combine(_directory, FileName);

    public static string DefaultDirectory()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(local, AppFolderName);
    }

    public static string LegacyDirectory()
    {
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(local, LegacyFolderName);
    }

    public IReadOnlyList<AccountRecord> Load()
    {
        var path = File.Exists(FilePath) ? FilePath : LegacyFilePath();
        if (path is null || !File.Exists(path))
        {
            return Array.Empty<AccountRecord>();
        }

        var cipher = File.ReadAllBytes(path);
        var plain = _protector.Unprotect(cipher, Entropy);
        var json = Encoding.UTF8.GetString(plain);
        var records = JsonSerializer.Deserialize<List<AccountRecord>>(json, JsonOptions);
        return records is null ? Array.Empty<AccountRecord>() : records;
    }

    public void Save(IEnumerable<AccountRecord> records)
    {
        Directory.CreateDirectory(_directory);
        var json = JsonSerializer.Serialize(records.ToList());
        var cipher = _protector.Protect(Encoding.UTF8.GetBytes(json), Entropy);

        var temp = Path.Combine(_directory, FileName + "." + Guid.NewGuid().ToString("N") + ".tmp");
        File.WriteAllBytes(temp, cipher);
        File.Move(temp, FilePath, overwrite: true);
    }

    private string? LegacyFilePath()
    {
        var legacy = Path.Combine(Path.GetDirectoryName(_directory) ?? string.Empty, LegacyFolderName, FileName);
        return File.Exists(legacy) ? legacy : null;
    }
}
