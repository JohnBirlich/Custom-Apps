using System.Diagnostics;
using System.IO;
using System.Windows;
using UUF.App.ViewModels;
using UUF.Core.Diagnostics;

namespace UUF.App.Windows;

public partial class JournalWindow : Window
{
    private readonly JournalViewModel _viewModel;

    public JournalWindow(AppLog log)
    {
        InitializeComponent();
        _viewModel = new JournalViewModel(log);
        DataContext = _viewModel;
        Closed += (_, _) => _viewModel.Detach();
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        var path = _viewModel.LogPath;
        if (File.Exists(path))
        {
            Process.Start("explorer.exe", "/select,\"" + path + "\"");
        }
        else
        {
            MessageBox.Show(this, "Файл журнала ещё не создан.", "UUF", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
}
