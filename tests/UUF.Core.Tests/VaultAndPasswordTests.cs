using System.Text;
using UUF.Core.Security;
using UUF.Core.Vault;
using Xunit;

namespace UUF.Core.Tests;

internal sealed class ReversibleProtector : ISecretProtector
{
    public List<byte[]> EntropyUsed { get; } = new();

    public byte[] Protect(byte[] plain, byte[] entropy)
    {
        EntropyUsed.Add(entropy);
        return Encoding.UTF8.GetBytes("enc:" + Convert.ToBase64String(plain));
    }

    public byte[] Unprotect(byte[] cipher, byte[] entropy)
    {
        var text = Encoding.UTF8.GetString(cipher);
        return Convert.FromBase64String(text.Substring("enc:".Length));
    }
}

public class PasswordGeneratorTests
{
    [Theory]
    [InlineData(16)]
    [InlineData(20)]
    [InlineData(32)]
    public void HasRequestedLengthAndAllCharacterClasses(int length)
    {
        for (var attempt = 0; attempt < 50; attempt++)
        {
            var password = PasswordGenerator.Generate(length);

            Assert.Equal(length, password.Length);
            Assert.Contains(password, c => char.IsUpper(c));
            Assert.Contains(password, c => char.IsLower(c));
            Assert.Contains(password, c => char.IsDigit(c));
            Assert.Contains(password, c => "!@#$%^&*-_=+?".Contains(c));
        }
    }

    [Fact]
    public void AvoidsAmbiguousCharacters()
    {
        for (var attempt = 0; attempt < 50; attempt++)
        {
            var password = PasswordGenerator.Generate(32);
            Assert.DoesNotContain(password, c => "0O1lI".Contains(c));
        }
    }

    [Theory]
    [InlineData(15)]
    [InlineData(33)]
    public void RejectsLengthOutsideRange(int length)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => PasswordGenerator.Generate(length));
    }

    [Fact]
    public void ProducesDifferentPasswords()
    {
        var first = PasswordGenerator.Generate(24);
        var second = PasswordGenerator.Generate(24);
        Assert.NotEqual(first, second);
    }
}

public class AccountVaultTests
{
    private static string NewTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), "uuf-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    [Fact]
    public void SaveThenLoadRoundTrips()
    {
        var directory = NewTempDirectory();
        try
        {
            var protector = new ReversibleProtector();
            var vault = new AccountVault(directory, protector);
            var records = new[]
            {
                new AccountRecord("neo@gmail.com", "Pa$$w0rd-1", "Google", "2026-10-31T10:00:00.0000000+03:00"),
            };

            vault.Save(records);
            var loaded = vault.Load();

            Assert.Equal(records, loaded);
            Assert.All(protector.EntropyUsed, entropy => Assert.Equal(AccountVault.Entropy, entropy));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void ReadsRecordsWrittenByPowerShellVersion()
    {
        var directory = NewTempDirectory();
        try
        {
            var psJson = "[{\"Username\":\"neo@mail.ru\",\"Password\":\"x1\",\"Platform\":\"Mail.ru\",\"CreatedAt\":\"2026-10-30T12:00:00.0000000+03:00\"}]";
            var protector = new ReversibleProtector();
            var cipher = protector.Protect(Encoding.UTF8.GetBytes(psJson), AccountVault.Entropy);
            File.WriteAllBytes(Path.Combine(directory, AccountVault.FileName), cipher);

            var loaded = new AccountVault(directory, protector).Load();

            var record = Assert.Single(loaded);
            Assert.Equal("neo@mail.ru", record.Username);
            Assert.Equal("x1", record.Password);
            Assert.Equal("Mail.ru", record.Platform);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void MissingFileGivesEmptyList()
    {
        var directory = NewTempDirectory();
        try
        {
            var loaded = new AccountVault(directory, new ReversibleProtector()).Load();
            Assert.Empty(loaded);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void SaveReplacesPreviousContent()
    {
        var directory = NewTempDirectory();
        try
        {
            var vault = new AccountVault(directory, new ReversibleProtector());
            vault.Save(new[] { new AccountRecord("a", "p1", "Steam", "t") });
            vault.Save(Array.Empty<AccountRecord>());

            Assert.Empty(vault.Load());
            Assert.Single(Directory.GetFiles(directory));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
