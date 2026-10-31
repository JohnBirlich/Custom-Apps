using System.Security.Cryptography;
using System.Text;

namespace UUF.Core.Security;

public static class PasswordGenerator
{
    public const int MinLength = 16;
    public const int MaxLength = 32;

    private const string Upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
    private const string Lower = "abcdefghjkmnpqrstuvwxyz";
    private const string Digits = "23456789";
    private const string Special = "!@#$%^&*-_=+?";

    public static string Generate(int length = 20)
    {
        if (length < MinLength || length > MaxLength)
        {
            throw new ArgumentOutOfRangeException(nameof(length), $"Длина от {MinLength} до {MaxLength}.");
        }

        var all = Upper + Lower + Digits + Special;
        var characters = new List<char>(length)
        {
            Pick(Upper),
            Pick(Lower),
            Pick(Digits),
            Pick(Special),
        };
        while (characters.Count < length)
        {
            characters.Add(Pick(all));
        }

        for (var i = characters.Count - 1; i > 0; i--)
        {
            var j = RandomNumberGenerator.GetInt32(i + 1);
            (characters[i], characters[j]) = (characters[j], characters[i]);
        }

        var builder = new StringBuilder(length);
        foreach (var character in characters)
        {
            builder.Append(character);
        }
        return builder.ToString();
    }

    private static char Pick(string alphabet)
    {
        return alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)];
    }
}
