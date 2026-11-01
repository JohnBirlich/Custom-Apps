using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

internal static class UufLauncher
{
    private const string ScriptResourceName = "UniversalUsernameFinder.ps1";

    private static int Main()
    {
        string localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string appDirectory = Path.Combine(localData, "UniversalUsernameFinder", "app");
        Directory.CreateDirectory(appDirectory);

        string scriptPath = Path.Combine(appDirectory, ScriptResourceName);
        byte[] scriptBytes = ReadEmbeddedScript();
        if (!SameContent(scriptPath, scriptBytes))
        {
            File.WriteAllBytes(scriptPath, scriptBytes);
        }

        string powershell = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
        string arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File \"" + scriptPath + "\"";

        ProcessStartInfo startInfo = new ProcessStartInfo(powershell, arguments);
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WorkingDirectory = appDirectory;

        using (Process process = Process.Start(startInfo))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static byte[] ReadEmbeddedScript()
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ScriptResourceName))
        {
            if (stream == null)
            {
                throw new InvalidOperationException("Не найден встроенный скрипт приложения.");
            }
            using (MemoryStream buffer = new MemoryStream())
            {
                stream.CopyTo(buffer);
                return buffer.ToArray();
            }
        }
    }

    private static bool SameContent(string path, byte[] expected)
    {
        if (!File.Exists(path))
        {
            return false;
        }
        byte[] actual = File.ReadAllBytes(path);
        if (actual.Length != expected.Length)
        {
            return false;
        }
        for (int i = 0; i < actual.Length; i++)
        {
            if (actual[i] != expected[i])
            {
                return false;
            }
        }
        return true;
    }
}
