using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace UUF.App.Help;

public partial class HelpWindow : Window
{
    private readonly List<Button> _navButtons = new();

    public HelpWindow()
    {
        InitializeComponent();

        for (var index = 0; index < HelpContent.Pages.Count; index++)
        {
            var button = new Button
            {
                Content = HelpContent.Pages[index].Title,
                Tag = index,
                FontWeight = FontWeights.Bold,
                FontSize = 15,
                Height = 44,
                Margin = new Thickness(0, 0, index == HelpContent.Pages.Count - 1 ? 0 : 8, 0),
                Padding = new Thickness(8, 4, 8, 4),
            };
            button.Click += (_, _) => ShowPage((int)button.Tag);
            NavGrid.Children.Add(button);
            _navButtons.Add(button);
        }

        ShowPage(0);
    }

    private void ShowPage(int index)
    {
        CardsHost.ItemsSource = HelpContent.Pages[index].Cards;
        foreach (var button in _navButtons)
        {
            var selected = (int)button.Tag == index;
            button.Background = (Brush)FindResource(selected ? "ControlSelectedBrush" : "ControlBrush");
            button.BorderBrush = (Brush)FindResource(selected ? "AccentBrush" : "BorderBrush");
        }
    }
}
