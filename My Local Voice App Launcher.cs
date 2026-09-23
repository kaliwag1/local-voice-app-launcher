// Startup window for the desktop shortcut. It runs Start My Voice App.ps1 hidden, shows
// its progress, and gets out of the way once the app window is up.
//
// Everything is painted by hand to match the app (dark surface, purple accent), because
// stock WinForms controls only come in the Windows 95 look. The script reports progress
// by rewriting "Last Voice App Start.txt"; each status line is mapped to one of four steps.
//
// Build (C# 5 - the compiler that ships with .NET Framework):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe
//     /win32icon:launcher.ico /r:System.Windows.Forms.dll /r:System.Drawing.dll
//     /out:"My Local Voice App Launcher.exe" "My Local Voice App Launcher.cs"
// Preview without starting anything:  "My Local Voice App Launcher.exe" --preview 2
//   (step 0-4, add --fail for the error state, --snapshot file.png to save and exit)
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class Program
{
    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    [STAThread]
    private static void Main(string[] args)
    {
        try { SetProcessDPIAware(); } catch (EntryPointNotFoundException) { }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new StartupWindow(args));
    }
}

internal static class Palette
{
    public static readonly Color Surface = Color.FromArgb(14, 16, 24);
    public static readonly Color SurfaceRaised = Color.FromArgb(22, 23, 32);
    public static readonly Color Border = Color.FromArgb(40, 255, 255, 255);
    public static readonly Color Divider = Color.FromArgb(22, 255, 255, 255);
    public static readonly Color Text = Color.FromArgb(242, 239, 255);
    public static readonly Color Text2 = Color.FromArgb(205, 200, 220);
    public static readonly Color Text3 = Color.FromArgb(165, 161, 179);
    public static readonly Color Text4 = Color.FromArgb(118, 114, 134);
    public static readonly Color Accent = Color.FromArgb(115, 88, 232);
    public static readonly Color AccentBright = Color.FromArgb(163, 138, 255);
    public static readonly Color Success = Color.FromArgb(80, 223, 171);
    public static readonly Color Danger = Color.FromArgb(255, 123, 130);
}

internal sealed class StartupWindow : Form
{
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    private const int WmNcLButtonDown = 0xA1;
    private const int HtCaption = 2;
    private const int DwmUseImmersiveDarkMode = 20;
    private const int DwmWindowCornerPreference = 33;
    private const int DwmCornerRound = 2;

    private enum StepState { Pending, Active, Done, Failed }

    // The error state needs room for its message and two buttons; progress does not.
    private const int RunningHeight = 304;
    private const int FailedHeight = 340;

    private static readonly string[] StepTitles = { "Check setup", "Load the model", "Start speech", "Open the app" };
    // Share of the bar each step covers; loading the model is usually the long one.
    private static readonly float[] StepWeights = { 0.06f, 0.46f, 0.30f, 0.18f };
    // How quickly the bar creeps through a step while waiting (seconds to ~63%).
    private static readonly float[] StepPatience = { 2f, 18f, 12f, 5f };

    private readonly string root = AppDomain.CurrentDomain.BaseDirectory;
    private readonly Timer frameTimer = new Timer();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly float scale;
    private readonly Font titleFont;
    private readonly Font subtitleFont;
    private readonly Font stepFont;
    private readonly Font detailFont;
    private readonly Font buttonFont;
    private readonly Font markFont;

    private readonly bool preview;
    private readonly string snapshotPath;

    private string stepTwoTitle = StepTitles[2];
    private string status = "Checking local services...";
    private int step;
    private bool failed;
    private bool finished;
    private double stepStartedAt;
    private float shownProgress;
    private double lastPoll = -1;
    private bool scriptFinished;
    private bool scriptSucceeded;
    private DateTime windowDeadline;
    private DateTime closeAt = DateTime.MaxValue;

    private Rectangle closeBox;
    private Rectangle logButton;
    private Rectangle dismissButton;
    private string hover = "";

    public StartupWindow(string[] args)
    {
        preview = Array.IndexOf(args, "--preview") >= 0;
        int previewStep = 0;
        int index = Array.IndexOf(args, "--preview");
        if (preview && index + 1 < args.Length) int.TryParse(args[index + 1], out previewStep);
        index = Array.IndexOf(args, "--snapshot");
        if (index >= 0 && index + 1 < args.Length) snapshotPath = args[index + 1];

        using (var graphics = CreateGraphics()) scale = graphics.DpiX / 96f;
        titleFont = new Font("Segoe UI Semibold", 12.5f, FontStyle.Regular);
        subtitleFont = new Font("Segoe UI", 9f);
        stepFont = new Font("Segoe UI", 9.75f);
        detailFont = new Font("Segoe UI", 8.75f);
        buttonFont = new Font("Segoe UI Semibold", 9f);
        markFont = new Font("Segoe UI", 10f, FontStyle.Bold);

        Text = "My Local Voice App";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(S(440), S(RunningHeight));
        BackColor = Palette.Surface;
        DoubleBuffered = true;
        TopMost = true;
        KeyPreview = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);

        frameTimer.Interval = 33;
        frameTimer.Tick += (sender, e) => Frame();
        MouseDown += OnMouseDownDrag;
        MouseMove += (sender, e) => UpdateHover(e.Location);
        MouseLeave += (sender, e) => UpdateHover(new Point(-1, -1));
        MouseUp += OnClick;
        KeyDown += (sender, e) => { if (e.KeyCode == Keys.Escape && failed) Close(); };
        Shown += (sender, e) => Begin();

        if (preview) {
            step = Math.Max(0, Math.Min(4, previewStep));
            failed = Array.IndexOf(args, "--fail") >= 0;
            if (failed) status = "The selected model did not load. Check that LM Studio is installed and the model is downloaded.";
            else if (step >= 4) { finished = true; status = "Ready"; }
            else status = PreviewStatus(step);
            if (Array.IndexOf(args, "--text") >= 0) stepTwoTitle = "Start chat (text only)";
            shownProgress = ProgressFor(step, 5);
            if (failed) ClientSize = new Size(S(440), S(FailedHeight));
        }
    }

    // Rounded corners, a shadow and a dark title strip on Windows 11; harmless elsewhere.
    protected override CreateParams CreateParams
    {
        get {
            var parameters = base.CreateParams;
            parameters.ClassStyle |= 0x20000; // CS_DROPSHADOW
            return parameters;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        try {
            int round = DwmCornerRound;
            DwmSetWindowAttribute(Handle, DwmWindowCornerPreference, ref round, sizeof(int));
            int dark = 1;
            DwmSetWindowAttribute(Handle, DwmUseImmersiveDarkMode, ref dark, sizeof(int));
        } catch (DllNotFoundException) { }
    }

    private int S(float value) { return (int)Math.Round(value * scale); }

    private static string PreviewStatus(int value)
    {
        switch (value) {
            case 1: return "Loading local model...";
            case 2: return "Starting local speech...";
            case 3: return "Opening voice app...";
            default: return "Checking local voice app...";
        }
    }

    private void Begin()
    {
        frameTimer.Start();
        if (snapshotPath != null) {
            Frame();
            SaveSnapshot(snapshotPath);
            Close();
            return;
        }
        if (!preview) StartLauncher();
    }

    private void SaveSnapshot(string path)
    {
        using (var bitmap = new Bitmap(ClientSize.Width, ClientSize.Height)) {
            DrawToBitmap(bitmap, new Rectangle(Point.Empty, ClientSize));
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    private void StartLauncher()
    {
        var script = Path.Combine(root, "Start My Voice App.ps1");
        if (!File.Exists(script)) {
            Fail("The startup script is missing from the app folder.");
            return;
        }
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

    // Runs every frame: animation always, the script's status file twice a second.
    private void Frame()
    {
        double now = clock.Elapsed.TotalSeconds;
        if (!preview && !failed && !finished && now - lastPoll >= 0.5) {
            lastPoll = now;
            PollStartup();
        }
        if (finished && DateTime.UtcNow >= closeAt) {
            Close();
            return;
        }
        float target = failed ? shownProgress : finished ? 1f : ProgressFor(step, now - stepStartedAt);
        if (!preview) shownProgress += (target - shownProgress) * 0.12f;
        Invalidate();
    }

    private static float ProgressFor(int value, double secondsInStep)
    {
        if (value >= StepWeights.Length) return 1f;
        float before = 0;
        for (int i = 0; i < value; i++) before += StepWeights[i];
        double creep = 1 - Math.Exp(-secondsInStep / StepPatience[value]);
        // Never quite reaches the next step on its own; the status file moves it on.
        return before + StepWeights[value] * (float)(0.9 * creep);
    }

    private void PollStartup()
    {
        var log = Path.Combine(root, "Last Voice App Start.txt");
        try {
            if (File.Exists(log)) SetStatus(File.ReadAllText(log, Encoding.UTF8).Trim());
        } catch (IOException) { }

        // The script launches the app before speech has finished loading and then keeps
        // checking on speech, so the app window can be up while the script still runs.
        if ((step >= 3 || (scriptFinished && scriptSucceeded)) && BringAppForward()) {
            Finish();
            return;
        }
        if (!scriptFinished) return;
        if (!scriptSucceeded) {
            Fail(status.StartsWith("Failed: ") ? status.Substring(8) : status);
            return;
        }
        SetStatus("Waiting for the app window...");
        if (DateTime.UtcNow > windowDeadline) Fail("The app started, but its window did not open.");
    }

    private bool BringAppForward()
    {
        foreach (var process in Process.GetProcessesByName("Qwen Audio Agent")) {
            try {
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                ShowWindow(process.MainWindowHandle, 9);
                SetForegroundWindow(process.MainWindowHandle);
                return true;
            } finally { process.Dispose(); }
        }
        return false;
    }

    private void SetStatus(string text)
    {
        if (string.IsNullOrEmpty(text) || text == status) return;
        status = text;
        if (text.StartsWith("Failed: ")) return;
        if (text.IndexOf("text only", StringComparison.OrdinalIgnoreCase) >= 0) stepTwoTitle = "Start chat (text only)";
        int next = StepFor(text);
        if (next > step) {
            step = next;
            stepStartedAt = clock.Elapsed.TotalSeconds;
        }
    }

    // The launcher script's status lines, by the step they belong to.
    private static int StepFor(string text)
    {
        string lower = text.ToLowerInvariant();
        if (lower.Contains("opening voice app") || lower.Contains("launch requested") || lower.Contains("waiting for the app")
            || lower.Contains("bringing open voice app") || lower.Contains("existing app window")) return 3;
        if (lower.Contains("local speech") || lower.Contains("local chat")) return 2;
        if (lower.Contains("bonsai") || lower.Contains("lm studio") || lower.Contains("model")) return 1;
        return 0;
    }

    private void Finish()
    {
        finished = true;
        step = StepTitles.Length;
        status = "Ready";
        closeAt = DateTime.UtcNow.AddMilliseconds(450);
    }

    private void Fail(string reason)
    {
        failed = true;
        status = string.IsNullOrEmpty(reason) ? "Startup failed." : reason;
        ClientSize = new Size(ClientSize.Width, S(FailedHeight));
        Invalidate();
    }

    // ---- input -------------------------------------------------------------------

    private void OnMouseDownDrag(object sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left || HitTest(e.Location) != "") return;
        ReleaseCapture();
        SendMessage(Handle, WmNcLButtonDown, (IntPtr)HtCaption, IntPtr.Zero);
    }

    private string HitTest(Point point)
    {
        if (closeBox.Contains(point)) return "close";
        if (failed && logButton.Contains(point)) return "log";
        if (failed && dismissButton.Contains(point)) return "dismiss";
        return "";
    }

    private void UpdateHover(Point point)
    {
        var next = HitTest(point);
        Cursor = next == "" ? Cursors.Default : Cursors.Hand;
        if (next == hover) return;
        hover = next;
        Invalidate();
    }

    private void OnClick(object sender, MouseEventArgs e)
    {
        switch (HitTest(e.Location)) {
            case "close":
            case "dismiss":
                Close();
                break;
            case "log":
                var log = Path.Combine(root, "Last Voice App Start.txt");
                if (File.Exists(log)) Process.Start(log);
                break;
        }
    }

    // ---- painting ----------------------------------------------------------------

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        double now = clock.Elapsed.TotalSeconds;

        PaintBackground(g);
        PaintHeader(g);
        PaintSteps(g, now);
        PaintFooter(g, now);
    }

    private void PaintBackground(Graphics g)
    {
        var bounds = ClientRectangle;
        g.Clear(Palette.Surface);
        // A soft accent glow in the top-left corner, like the app's panels.
        using (var glow = new GraphicsPath()) {
            glow.AddEllipse(-S(140), -S(170), S(420), S(340));
            using (var brush = new PathGradientBrush(glow)) {
                brush.CenterColor = Color.FromArgb(46, Palette.Accent);
                brush.SurroundColors = new[] { Color.FromArgb(0, Palette.Accent) };
                g.FillPath(brush, glow);
            }
        }
        using (var pen = new Pen(Palette.Border, 1)) {
            g.DrawRectangle(pen, 0, 0, bounds.Width - 1, bounds.Height - 1);
        }
    }

    private void PaintHeader(Graphics g)
    {
        int left = S(24);
        int top = S(22);
        var mark = new Rectangle(left, top, S(38), S(38));
        using (var path = RoundedRect(mark, S(10)))
        using (var brush = new LinearGradientBrush(mark, Palette.AccentBright, Palette.Accent, 135f)) {
            using (var glow = new Pen(Color.FromArgb(60, Palette.Accent), S(6))) {
                glow.LineJoin = LineJoin.Round;
                g.DrawPath(glow, path);
            }
            g.FillPath(brush, path);
        }
        TextRenderer.DrawText(g, "ZD", markFont, mark, Color.White,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);

        int textLeft = mark.Right + S(14);
        TextRenderer.DrawText(g, failed ? "Couldn't start" : finished ? "Ready" : "Starting My Local Voice App",
            titleFont, new Point(textLeft, top - S(1)), Palette.Text, TextFormatFlags.NoPadding);
        TextRenderer.DrawText(g, failed ? "Something went wrong along the way." : "Everything runs on this PC.",
            subtitleFont, new Point(textLeft, top + S(22)), Palette.Text3, TextFormatFlags.NoPadding);

        closeBox = new Rectangle(ClientSize.Width - S(40), S(14), S(26), S(26));
        if (hover == "close") {
            using (var path = RoundedRect(closeBox, S(7)))
            using (var brush = new SolidBrush(Color.FromArgb(22, 255, 255, 255))) g.FillPath(brush, path);
        }
        using (var pen = new Pen(hover == "close" ? Palette.Text : Palette.Text4, S(1.4f))) {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            int c = S(5);
            var center = new Point(closeBox.X + closeBox.Width / 2, closeBox.Y + closeBox.Height / 2);
            g.DrawLine(pen, center.X - c, center.Y - c, center.X + c, center.Y + c);
            g.DrawLine(pen, center.X + c, center.Y - c, center.X - c, center.Y + c);
        }
    }

    private void PaintSteps(Graphics g, double now)
    {
        int left = S(24);
        int top = S(84);
        int rowHeight = S(34);
        var card = new Rectangle(left, top, ClientSize.Width - left * 2, rowHeight * StepTitles.Length + S(12));
        using (var path = RoundedRect(card, S(12)))
        using (var brush = new SolidBrush(Color.FromArgb(150, Palette.SurfaceRaised)))
        using (var pen = new Pen(Palette.Divider, 1)) {
            g.FillPath(brush, path);
            g.DrawPath(pen, path);
        }

        for (int i = 0; i < StepTitles.Length; i++) {
            var state = StateOf(i);
            int y = top + S(6) + i * rowHeight;
            var dot = new Rectangle(left + S(14), y + (rowHeight - S(18)) / 2, S(18), S(18));
            PaintStepIcon(g, dot, state, now);
            string title = i == 2 ? stepTwoTitle : StepTitles[i];
            var color = state == StepState.Pending ? Palette.Text4
                : state == StepState.Failed ? Palette.Danger
                : state == StepState.Active ? Palette.Text : Palette.Text2;
            TextRenderer.DrawText(g, title, stepFont,
                new Rectangle(dot.Right + S(12), y, S(200), rowHeight), color,
                TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            if (state == StepState.Active && !preview) {
                double seconds = now - stepStartedAt;
                if (seconds >= 3) {
                    TextRenderer.DrawText(g, FormatSeconds(seconds), detailFont,
                        new Rectangle(card.Right - S(80), y, S(66), rowHeight), Palette.Text4,
                        TextFormatFlags.VerticalCenter | TextFormatFlags.Right | TextFormatFlags.NoPadding);
                }
            }
        }
    }

    private StepState StateOf(int index)
    {
        if (finished || index < step) return StepState.Done;
        if (index == step) return failed ? StepState.Failed : StepState.Active;
        return StepState.Pending;
    }

    private void PaintStepIcon(Graphics g, Rectangle box, StepState state, double now)
    {
        switch (state) {
            case StepState.Done:
                using (var brush = new SolidBrush(Color.FromArgb(38, Palette.Success))) g.FillEllipse(brush, box);
                using (var pen = new Pen(Palette.Success, S(1.8f))) {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    g.DrawLines(pen, new[] {
                        new PointF(box.X + box.Width * 0.28f, box.Y + box.Height * 0.52f),
                        new PointF(box.X + box.Width * 0.44f, box.Y + box.Height * 0.68f),
                        new PointF(box.X + box.Width * 0.73f, box.Y + box.Height * 0.36f),
                    });
                }
                break;
            case StepState.Failed:
                using (var brush = new SolidBrush(Color.FromArgb(40, Palette.Danger))) g.FillEllipse(brush, box);
                using (var pen = new Pen(Palette.Danger, S(1.8f))) {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    float a = box.Width * 0.32f;
                    float b = box.Width * 0.68f;
                    g.DrawLine(pen, box.X + a, box.Y + a, box.X + b, box.Y + b);
                    g.DrawLine(pen, box.X + b, box.Y + a, box.X + a, box.Y + b);
                }
                break;
            case StepState.Active:
                using (var track = new Pen(Color.FromArgb(45, Palette.Accent), S(2)))
                    g.DrawEllipse(track, Inset(box, S(1)));
                using (var arc = new Pen(Palette.AccentBright, S(2))) {
                    arc.StartCap = LineCap.Round;
                    arc.EndCap = LineCap.Round;
                    float angle = (float)(now * 360 % 360);
                    g.DrawArc(arc, Inset(box, S(1)), angle, 100);
                }
                break;
            default:
                using (var pen = new Pen(Color.FromArgb(55, 255, 255, 255), S(1.5f)))
                    g.DrawEllipse(pen, Inset(box, S(2)));
                break;
        }
    }

    private void PaintFooter(Graphics g, double now)
    {
        int left = S(24);
        int width = ClientSize.Width - left * 2;
        int top = S(244);

        // Status line from the script, and the overall time on the right.
        var statusColor = failed ? Palette.Danger : Palette.Text3;
        string shown = failed || finished ? status : Friendly(status);
        var statusBox = new Rectangle(left, top, width - (failed ? 0 : S(52)), failed ? S(34) : S(18));
        TextRenderer.DrawText(g, shown, detailFont, statusBox, statusColor,
            (failed ? TextFormatFlags.WordBreak : TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine) | TextFormatFlags.NoPadding);
        if (!failed && !preview) {
            TextRenderer.DrawText(g, FormatSeconds(now), detailFont,
                new Rectangle(left + width - S(48), top, S(48), S(18)), Palette.Text4,
                TextFormatFlags.Right | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        }

        if (failed) {
            PaintButtons(g, left, width);
            return;
        }

        // Progress bar: a rounded track, the filled part in the accent, and a light
        // sweeping across it while work is going on.
        var track = new Rectangle(left, top + S(30), width, S(6));
        using (var path = RoundedRect(track, track.Height / 2))
        using (var brush = new SolidBrush(Color.FromArgb(26, 255, 255, 255))) g.FillPath(brush, path);
        int filled = Math.Max(track.Height, (int)(track.Width * Math.Min(1f, shownProgress)));
        var fill = new Rectangle(track.X, track.Y, filled, track.Height);
        using (var path = RoundedRect(fill, track.Height / 2)) {
            using (var brush = new LinearGradientBrush(new Rectangle(track.X - 1, track.Y, track.Width + 2, track.Height),
                finished ? Palette.Success : Palette.Accent, finished ? Palette.Success : Palette.AccentBright, 0f))
                g.FillPath(brush, path);
            if (!finished) {
                float sweep = (float)((now * 0.6) % 1.4 - 0.2) * track.Width;
                var shine = new RectangleF(track.X + sweep - S(40), track.Y, S(80), track.Height);
                using (var brush = new LinearGradientBrush(shine, Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 0f)) {
                    var blend = new ColorBlend {
                        Colors = new[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(90, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) },
                        Positions = new[] { 0f, 0.5f, 1f },
                    };
                    brush.InterpolationColors = blend;
                    var clip = g.Clip;
                    g.SetClip(path);
                    g.FillRectangle(brush, shine);
                    g.Clip = clip;
                }
            }
        }
    }

    private void PaintButtons(Graphics g, int left, int width)
    {
        int top = ClientSize.Height - S(56);
        dismissButton = new Rectangle(left + width - S(84), top, S(84), S(34));
        logButton = new Rectangle(dismissButton.X - S(10) - S(132), top, S(132), S(34));
        PaintButton(g, logButton, "Open startup log", hover == "log", false);
        PaintButton(g, dismissButton, "Close", hover == "dismiss", true);
    }

    private void PaintButton(Graphics g, Rectangle box, string label, bool hovered, bool primary)
    {
        using (var path = RoundedRect(box, S(9))) {
            var fill = primary
                ? (hovered ? Palette.AccentBright : Palette.Accent)
                : Color.FromArgb(hovered ? 30 : 16, 255, 255, 255);
            using (var brush = new SolidBrush(fill)) g.FillPath(brush, path);
            if (!primary) using (var pen = new Pen(Palette.Border, 1)) g.DrawPath(pen, path);
        }
        TextRenderer.DrawText(g, label, buttonFont, box, primary ? Color.White : Palette.Text2,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
    }

    // The script's own wording, tidied: no trailing dots, and plain English for the
    // two lines that mean "done".
    private static string Friendly(string text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        if (text == "App launch requested.") return "Waiting for the app window";
        return text.TrimEnd('.', ' ');
    }

    private static string FormatSeconds(double seconds)
    {
        int total = (int)seconds;
        return (total / 60) + ":" + (total % 60).ToString("00");
    }

    private static Rectangle Inset(Rectangle box, int by)
    {
        return new Rectangle(box.X + by, box.Y + by, box.Width - by * 2, box.Height - by * 2);
    }

    private static GraphicsPath RoundedRect(Rectangle box, int radius)
    {
        var path = new GraphicsPath();
        int d = Math.Max(1, Math.Min(radius * 2, Math.Min(box.Width, box.Height)));
        path.AddArc(box.X, box.Y, d, d, 180, 90);
        path.AddArc(box.Right - d, box.Y, d, d, 270, 90);
        path.AddArc(box.Right - d, box.Bottom - d, d, d, 0, 90);
        path.AddArc(box.X, box.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
