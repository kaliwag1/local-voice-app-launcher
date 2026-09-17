using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new StartupWindow());
    }
}

internal sealed class StartupWindow : Form
{
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    private readonly string root = AppDomain.CurrentDomain.BaseDirectory;
    private readonly Label status = new Label();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly Button openLog = new Button();
    private readonly Timer timer = new Timer();
    private bool scriptFinished;
    private bool scriptSucceeded;
    private DateTime windowDeadline;

    public StartupWindow()
    {
        Text = "My Local Voice App";
        ClientSize = new Size(440, 148);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;

        var heading = new Label {
            Text = "Starting My Local Voice App",
            Font = new Font("Segoe UI", 12, FontStyle.Bold),
            AutoSize = true,
            Location = new Point(18, 18)
        };
        status.Text = "Checking local services...";
        status.Font = new Font("Segoe UI", 9);
        status.AutoEllipsis = true;
        status.Location = new Point(20, 59);
        status.Size = new Size(400, 24);
        progress.Style = ProgressBarStyle.Marquee;
        progress.Location = new Point(20, 96);
        progress.Size = new Size(400, 15);
        openLog.Text = "Open startup log";
        openLog.Location = new Point(290, 109);
        openLog.Size = new Size(130, 28);
        openLog.Visible = false;
        openLog.Click += (sender, args) => Process.Start(Path.Combine(root, "Last Voice App Start.txt"));

        Controls.Add(heading);
        Controls.Add(status);
        Controls.Add(progress);
        Controls.Add(openLog);
        timer.Interval = 500;
        timer.Tick += (sender, args) => RefreshStartupState();
        Shown += (sender, args) => StartLauncher();
    }

    private void StartLauncher()
    {
        var script = Path.Combine(root, "Start My Voice App.ps1");
        if (!File.Exists(script)) {
            Fail("The startup script is missing from the app folder.");
            return;
        }

        timer.Start();
        Task.Run(() => {
            try {
                var start = new ProcessStartInfo {
                    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                                            "System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"",
                    WorkingDirectory = root,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                using (var process = Process.Start(start)) {
                    if (process == null) throw new Exception("The startup process could not be created.");
                    process.WaitForExit();
                    var succeeded = process.ExitCode == 0;
                    BeginInvoke((Action)(() => {
                        scriptFinished = true;
                        scriptSucceeded = succeeded;
                        windowDeadline = DateTime.UtcNow.AddSeconds(40);
                    }));
                }
            } catch (Exception error) {
                if (!IsDisposed) BeginInvoke((Action)(() => Fail(error.Message)));
            }
        });
    }

    private void RefreshStartupState()
    {
        var log = Path.Combine(root, "Last Voice App Start.txt");
        try {
            if (File.Exists(log)) status.Text = File.ReadAllText(log, Encoding.UTF8).Trim();
        } catch (IOException) { }

        if (!scriptFinished) return;
        if (!scriptSucceeded) {
            Fail(status.Text.StartsWith("Failed: ") ? status.Text.Substring(8) : status.Text);
            return;
        }

        foreach (var process in Process.GetProcessesByName("Qwen Audio Agent")) {
            try {
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                ShowWindow(process.MainWindowHandle, 9);
                SetForegroundWindow(process.MainWindowHandle);
                Close();
                return;
            } finally { process.Dispose(); }
        }
        status.Text = "Waiting for the app window...";
        if (DateTime.UtcNow > windowDeadline) Fail("The app started, but its window did not open.");
    }

    private void Fail(string reason)
    {
        timer.Stop();
        progress.Visible = false;
        status.Text = reason;
        openLog.Visible = true;
    }
}
