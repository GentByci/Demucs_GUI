using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

using WpfWindow = System.Windows.Window;
using WpfMessageBox = System.Windows.MessageBox;
using WpfMessageBoxBtn = System.Windows.MessageBoxButton;
using WpfMessageBoxImg = System.Windows.MessageBoxImage;
using WpfVisibility = System.Windows.Visibility;
using WpfRoutedArgs = System.Windows.RoutedEventArgs;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfWindowState = System.Windows.WindowState;

using System.Windows.Controls;
using System.Windows.Controls.Primitives;

using WinFormsFolderDlg = System.Windows.Forms.FolderBrowserDialog;
using WinFormsDialogResult = System.Windows.Forms.DialogResult;
using Win32OpenFileDialog = Microsoft.Win32.OpenFileDialog;

namespace DemucsGUI
{
    public partial class MainWindow : WpfWindow
    {
        // ── State ────────────────────────────────────────────────────────────
        private bool _isFullSeparation = true;
        private bool _useGpu = false;
        private string _selectedModel = "htdemucs";

        private readonly DemucsService _demucs = new();

        private readonly Dictionary<string, string> _modelDescriptions = new()
        {
            { "htdemucs",    "Default hybrid transformer model"          },
            { "htdemucs_ft", "Fine-tuned — higher quality, slower"       },
            { "htdemucs_6s", "6 stems: +guitar, piano"                   },
            { "hdemucs_mmi", "Hybrid Demucs + extra training data"       },
            { "mdx",         "MDX-Net competition model"                  },
            { "mdx_extra",   "MDX-Net with extra training data"           },
            { "mdx_q",       "Quantized MDX — faster"                    },
            { "mdx_extra_q", "Quantized MDX extra — best speed/quality"  },
        };

        // ── Init ─────────────────────────────────────────────────────────────
        public MainWindow()
        {
            InitializeComponent();
            ModelSelector.SelectionChanged += ModelSelector_SelectionChanged;
            InitDevicePanel();
            UpdateCommandPreview();
        }

        // ── Title bar ────────────────────────────────────────────────────────
        private void TitleBar_MouseLeftButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
            => DragMove();

        private void MinimizeButton_Click(object sender, WpfRoutedArgs e)
            => WindowState = WpfWindowState.Minimized;

        private void CloseButton_Click(object sender, WpfRoutedArgs e)
            => Close();

        // ── File / folder pickers ────────────────────────────────────────────
        private void BrowseInput_Click(object sender, WpfRoutedArgs e)
        {
            var dlg = new Win32OpenFileDialog
            {
                Filter = "Audio Files|*.mp3;*.wav;*.flac;*.ogg;*.m4a;*.aac|All Files|*.*",
                Title = "Select Audio File"
            };

            if (dlg.ShowDialog() != true) return;

            InputPathBox.Text = dlg.FileName;
            InputPathBox.Foreground = (WpfBrush)FindResource("BrushTextHi");

            if (OutputPathBox.Text == "No folder selected...")
            {
                string? dir = Path.GetDirectoryName(dlg.FileName);
                if (dir != null)
                {
                    OutputPathBox.Text = Path.Combine(dir, "separated");
                    OutputPathBox.Foreground = (WpfBrush)FindResource("BrushTextHi");
                }
            }

            UpdateCommandPreview();
        }

        private void BrowseOutput_Click(object sender, WpfRoutedArgs e)
        {
            var dlg = new WinFormsFolderDlg
            {
                Description = "Select Output Folder",
                UseDescriptionForTitle = true
            };

            if (dlg.ShowDialog() != WinFormsDialogResult.OK) return;

            OutputPathBox.Text = dlg.SelectedPath;
            OutputPathBox.Foreground = (WpfBrush)FindResource("BrushTextHi");
            UpdateCommandPreview();
        }

        // ── Toggles ──────────────────────────────────────────────────────────
        private void SeparationMode_Click(object sender, WpfRoutedArgs e)
        {
            _isFullSeparation = sender == FullSepToggle;
            FullSepToggle.IsChecked = _isFullSeparation;
            TwoStemToggle.IsChecked = !_isFullSeparation;
            UpdateCommandPreview();
        }

        private void DeviceMode_Click(object sender, WpfRoutedArgs e)
        {
            _useGpu = sender == GpuToggle;
            CpuToggle.IsChecked = !_useGpu;
            GpuToggle.IsChecked = _useGpu;
            UpdateCommandPreview();
        }

        // ── Device panel ─────────────────────────────────────────────────────
        private void InitDevicePanel()
        {
            var gpu = DemucsService.DetectGpu();
            if (gpu.Found)
            {
                DeviceStatus.Text = $"GPU: {gpu.DisplayName}";
                DeviceStatus.Foreground = (WpfBrush)FindResource("BrushTeal");
                GpuToggle.IsEnabled = true;
            }
            else
            {
                DeviceStatus.Text = "No GPU detected";
                DeviceStatus.Foreground = (WpfBrush)FindResource("BrushAsh");
                GpuToggle.IsEnabled = false;
            }

            if (DemucsService.FindVenvPython() == null)
            {
                DeviceStatus.Text = "⚠ demucs venv not found — check VenvCandidates";
                DeviceStatus.Foreground = WpfBrushes.IndianRed;
            }
        }

        // ── Model selector ────────────────────────────────────────────────────
        private void ModelSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (ModelDescription == null || ModelSelector?.SelectedItem is not ComboBoxItem item) return;

            _selectedModel = item.Content?.ToString() ?? "htdemucs";
            if (_modelDescriptions.TryGetValue(_selectedModel, out string? desc))
                ModelDescription.Text = desc;

            UpdateCommandPreview();
        }

        // ── Command preview ───────────────────────────────────────────────────
        private void UpdateCommandPreview()
        {
            if (CommandPreview == null) return;

            string input = InputPathBox?.Text is "No file selected..." or "" or null ? "" : InputPathBox.Text;
            string output = OutputPathBox?.Text is "No folder selected..." or "" or null ? "" : OutputPathBox.Text;

            CommandPreview.Text = DemucsService.BuildCommandPreview(
                input, output, _selectedModel, _useGpu, _isFullSeparation);
        }

        // ── Run button ────────────────────────────────────────────────────────
        private async void RunButton_Click(object sender, WpfRoutedArgs e)
        {
            if (string.IsNullOrWhiteSpace(InputPathBox.Text) || InputPathBox.Text == "No file selected...")
            {
                WpfMessageBox.Show("Please select an input file first.",
                    "Demucs Studio", WpfMessageBoxBtn.OK, WpfMessageBoxImg.Warning);
                return;
            }

            if (string.IsNullOrWhiteSpace(OutputPathBox.Text) || OutputPathBox.Text == "No folder selected...")
            {
                WpfMessageBox.Show("Please select an output folder.",
                    "Demucs Studio", WpfMessageBoxBtn.OK, WpfMessageBoxImg.Warning);
                return;
            }

            Directory.CreateDirectory(OutputPathBox.Text);

            // Lock UI, show progress card + log panel
            RunButton.IsEnabled = false;
            RunButton.Content = "Processing...";
            ProgressCard.Visibility = WpfVisibility.Visible;
            LogPanel.Visibility = WpfVisibility.Visible;   // ← live log
            LogBox.Clear();
            StatusText.Text = "Starting demucs...";
            StatusText.Foreground = (WpfBrush)FindResource("BrushAsh");

            string args = DemucsService.BuildArguments(
                InputPathBox.Text, OutputPathBox.Text, _selectedModel, _useGpu, _isFullSeparation);

            // Progress bar updates
            var progress = new Progress<DemucsService.ProgressUpdate>(update =>
            {
                StatusText.Text = update.StatusLine;
                if (update.Percent > 0) SetProgress(update.Percent);
            });

            // Live log: every stdout/stderr line appears in the log box
            void AppendLog(string line) =>
                Dispatcher.Invoke(() =>
                {
                    LogBox.AppendText(line + "\n");
                    LogBox.ScrollToEnd();
                });

            try
            {
                await _demucs.RunAsync(args, progress, AppendLog);

                StatusText.Text = "✓ Separation complete!";
                StatusText.Foreground = (WpfBrush)FindResource("BrushTeal");
                SetProgress(100);
            }
            catch (DemucsException ex)
            {
                // Show the last ~40 lines inline; offer to open the full log
                StatusText.Text = "✗ Error — see log below";
                StatusText.Foreground = WpfBrushes.IndianRed;

                var result = WpfMessageBox.Show(
                    ex.Message + $"\n\nOpen full log at:\n{DemucsService.LogPath}?",
                    "Demucs Error",
                    WpfMessageBoxBtn.YesNo,
                    WpfMessageBoxImg.Error);

                if (result == System.Windows.MessageBoxResult.Yes)
                    System.Diagnostics.Process.Start("notepad.exe", DemucsService.LogPath);
            }
            catch (Exception ex)
            {
                StatusText.Text = $"Error: {ex.Message}";
                StatusText.Foreground = WpfBrushes.IndianRed;
            }
            finally
            {
                RunButton.IsEnabled = true;
                RunButton.Content = "Separate Track";
            }
        }

        // ── Progress bar helper ───────────────────────────────────────────────
        private void SetProgress(int percent)
        {
            ProgressPercent.Text = $"{percent}%";
            ProgressTrack.UpdateLayout();
            ProgressFill.Width = Math.Max(0, ProgressTrack.ActualWidth * percent / 100.0);
        }
    }
}