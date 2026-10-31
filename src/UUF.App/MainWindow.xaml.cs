using System.Windows;
using UUF.App.ViewModels;
using UUF.App.Windows;
using UUF.Core.Security;
using UUF.Core.Vault;

namespace UUF.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
    }

    private void OpenAccounts_Click(object sender, RoutedEventArgs e)
    {
        var vault = new AccountVault(AccountVault.DefaultDirectory(), new DpapiProtector());
        var window = new AccountWindow(vault) { Owner = this };
        window.ShowDialog();
    }
}
