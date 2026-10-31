using System.Windows;
using UUF.App.ViewModels;
using UUF.App.Help;
using UUF.App.Windows;
using UUF.Core.Security;
using UUF.Core.Vault;

namespace UUF.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel(App.Log);
    }

    private void OpenAccounts_Click(object sender, RoutedEventArgs e)
    {
        var vault = new AccountVault(AccountVault.DefaultDirectory(), new DpapiProtector());
        var window = new AccountWindow(vault, App.Log) { Owner = this };
        window.ShowDialog();
    }

    private void OpenHelp_Click(object sender, RoutedEventArgs e)
    {
        var window = new HelpWindow { Owner = this };
        window.ShowDialog();
    }

    private void OpenJournal_Click(object sender, RoutedEventArgs e)
    {
        var window = new JournalWindow(App.Log) { Owner = this };
        window.Show();
    }
}
