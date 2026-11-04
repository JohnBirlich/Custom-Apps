using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;

internal static class UufLauncher
{
    private const string ScriptResourceName = "UniversalUsernameFinder.ps1";
    private static int exitCode = 0;

    [STAThread]
    private static int Main()
    {
        string localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string appDirectory = Path.Combine(localData, "UniversalUsernameFinder", "app");
        Directory.CreateDirectory(appDirectory);

        string script = ReadEmbeddedScript();

        Thread worker = new Thread(delegate() { RunScript(script, appDirectory); });
        worker.SetApartmentState(ApartmentState.STA);
        worker.Start();
        worker.Join();
        return exitCode;
    }

    private static void RunScript(string script, string appDirectory)
    {
        try
        {
            InitialSessionState state = InitialSessionState.CreateDefault();
            using (Runspace runspace = RunspaceFactory.CreateRunspace(state))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript(script);
                    shell.Invoke();
                }
            }
        }
        catch (Exception ex)
        {
            exitCode = 1;
            try
            {
                File.WriteAllText(Path.Combine(appDirectory, "launcher-error.log"), ex.ToString(), new UTF8Encoding(false));
            }
            catch (Exception)
            {
            }
        }
    }

    private static string ReadEmbeddedScript()
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
                string text = Encoding.UTF8.GetString(buffer.ToArray());
                if (text.Length > 0 && text[0] == '\uFEFF')
                {
                    text = text.Substring(1);
                }
                return text;
            }
        }
    }
}
