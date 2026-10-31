using System.Windows;
using System.Windows.Controls;
using UUF.App.ViewModels;
using UUF.Core.Vault;

namespace UUF.App.Windows;

public partial class AccountWindow : Window
{
    private readonly AccountViewModel _viewModel;

    public AccountWindow(AccountVault vault)
    {
        InitializeComponent();
        _viewModel = new AccountViewModel(vault);
        DataContext = _viewModel;
        ShowPanel(registerVisible: true);
    }

    private void RegisterTab_Click(object sender, RoutedEventArgs e)
    {
        ShowPanel(registerVisible: true);
    }

    private void VaultTab_Click(object sender, RoutedEventArgs e)
    {
        ShowPanel(registerVisible: false);
    }

    private void CopyPassword_Click(object sender, RoutedEventArgs e)
    {
        CopyToClipboard(_viewModel.Password);
    }

    private void CopySavedPassword_Click(object sender, RoutedEventArgs e)
    {
        CopyToClipboard(_viewModel.SelectedPassword);
    }

    private void ShowPanel(bool registerVisible)
    {
        RegisterPanel.Visibility = registerVisible ? Visibility.Visible : Visibility.Collapsed;
        VaultPanel.Visibility = registerVisible ? Visibility.Collapsed : Visibility.Visible;
        StyleNavButton(RegisterTabButton, registerVisible);
        StyleNavButton(VaultTabButton, !registerVisible);
    }

    private void StyleNavButton(Button button, bool selected)
    {
        button.Background = (System.Windows.Media.Brush)FindResource(selected ? "ControlSelectedBrush" : "ControlBrush");
        button.BorderBrush = (System.Windows.Media.Brush)FindResource(selected ? "AccentBrush" : "BorderBrush");
    }

    private void CopyToClipboard(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        try
        {
            Clipboard.SetText(text);
        }
        catch (System.Runtime.InteropServices.ExternalException)
        {
            MessageBox.Show(this, "Буфер обмена занят другой программой. Попробуйте ещё раз.", "UUF",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
