using System.Windows;
using UUF.App.ViewModels;

namespace UUF.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
    }
}
