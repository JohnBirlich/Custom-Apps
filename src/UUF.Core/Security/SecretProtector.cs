using System.Runtime.Versioning;
using System.Security.Cryptography;

namespace UUF.Core.Security;

public interface ISecretProtector
{
    byte[] Protect(byte[] plain, byte[] entropy);

    byte[] Unprotect(byte[] cipher, byte[] entropy);
}

[SupportedOSPlatform("windows")]
public sealed class DpapiProtector : ISecretProtector
{
    public byte[] Protect(byte[] plain, byte[] entropy)
    {
        return ProtectedData.Protect(plain, entropy, DataProtectionScope.CurrentUser);
    }

    public byte[] Unprotect(byte[] cipher, byte[] entropy)
    {
        return ProtectedData.Unprotect(cipher, entropy, DataProtectionScope.CurrentUser);
    }
}
