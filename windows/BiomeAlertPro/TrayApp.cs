using System.Media;

namespace BiomeAlertPro;

/// A hidden message-only window that hosts the tray icon, global hotkeys, and
/// the screen watcher. The app lives in the notification area.
public sealed class TrayApp : Form
{
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly NotifyIcon _tray;
    private readonly ScreenWatcher _watcher;
    private readonly ToolStripMenuItem _toggleItem;

    private const int HotkeyPause = 1;
    private const int HotkeyJoinLast = 2;
    private const int HotkeyClickNewest = 3;
    private const uint VK_P = 0x50, VK_J = 0x4A, VK_K = 0x4B;

    public TrayApp()
    {
        // Hidden window.
        WindowState = FormWindowState.Minimized;
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        Load += (_, _) => Visible = false;

        _watcher = new ScreenWatcher(_settings, Log);
        _watcher.BiomeJoined += OnBiomeJoined;

        _toggleItem = new ToolStripMenuItem("Pause", null, (_, _) => ToggleWatch());

        var menu = new ContextMenuStrip();
        menu.Items.Add(_toggleItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Settings…", null, (_, _) => ShowSettings()));
        menu.Items.Add(new ToolStripMenuItem("Join Last Link", null, (_, _) => JoinLast()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => Quit()));

        _tray = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Biome Alert Pro",
            Visible = true,
            ContextMenuStrip = menu
        };
        _tray.DoubleClick += (_, _) => ShowSettings();

        RegisterHotkeys();
        StartWatch();
    }

    // Create the native handle without ever showing the window.
    protected override void SetVisibleCore(bool value) => base.SetVisibleCore(false);

    private void RegisterHotkeys()
    {
        Native.RegisterHotKey(Handle, HotkeyPause, Native.MOD_CONTROL | Native.MOD_ALT, VK_P);
        Native.RegisterHotKey(Handle, HotkeyJoinLast, Native.MOD_CONTROL | Native.MOD_ALT, VK_J);
        Native.RegisterHotKey(Handle, HotkeyClickNewest, Native.MOD_CONTROL | Native.MOD_ALT, VK_K);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_HOTKEY)
        {
            switch ((int)m.WParam)
            {
                case HotkeyPause: ToggleWatch(); break;
                case HotkeyJoinLast: JoinLast(); break;
                case HotkeyClickNewest: _watcher.RequestManualClick(); break;
            }
        }
        base.WndProc(ref m);
    }

    private void StartWatch()
    {
        _watcher.Start();
        _toggleItem.Text = "Pause";
        _tray.Text = "Biome Alert Pro — watching";
    }

    private void ToggleWatch()
    {
        if (_watcher.Running) { _watcher.Stop(); _toggleItem.Text = "Start"; _tray.Text = "Biome Alert Pro — paused"; }
        else StartWatch();
    }

    private void JoinLast()
    {
        if (_watcher.LastLink is { } link)
        {
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo { FileName = link.LaunchTarget, UseShellExecute = true }); }
            catch (Exception ex) { Log("Join-last failed: " + ex.Message); }
        }
        else Log("No link detected yet.");
    }

    private void OnBiomeJoined(Biome biome)
    {
        if (_settings.PlaySound) SystemSounds.Exclamation.Play();
        if (_settings.NotifyOnDetect)
            _tray.ShowBalloonTip(4000, $"{biome.Display()} detected", "Joining server…", ToolTipIcon.Info);
    }

    private void ShowSettings()
    {
        using var form = new SettingsForm(_settings);
        if (form.ShowDialog() == DialogResult.OK) _settings.Save();
    }

    private void Log(string message)
    {
        // Surfaced via balloon for errors; kept simple for v1.
        if (message.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("unavailable", StringComparison.OrdinalIgnoreCase))
            _tray.ShowBalloonTip(4000, "Biome Alert Pro", message, ToolTipIcon.Warning);
    }

    private void Quit()
    {
        Native.UnregisterHotKey(Handle, HotkeyPause);
        Native.UnregisterHotKey(Handle, HotkeyJoinLast);
        Native.UnregisterHotKey(Handle, HotkeyClickNewest);
        _watcher.Stop();
        _watcher.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
        Application.Exit();
    }
}

/// A minimal settings window.
public sealed class SettingsForm : Form
{
    public SettingsForm(AppSettings s)
    {
        Text = "Biome Alert Pro — Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false; MinimizeBox = false;
        ClientSize = new Size(360, 380);

        var layout = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, Padding = new Padding(16), WrapContents = false };

        CheckBox Add(string text, bool value, Action<bool> set)
        {
            var cb = new CheckBox { Text = text, Checked = value, AutoSize = true, Margin = new Padding(0, 6, 0, 0) };
            cb.CheckedChanged += (_, _) => set(cb.Checked);
            layout.Controls.Add(cb);
            return cb;
        }

        layout.Controls.Add(new Label { Text = "Biomes to snipe", Font = new Font(Font, FontStyle.Bold), AutoSize = true });
        Add("Glitched", s.Glitched, v => s.Glitched = v);
        Add("Dreamspace", s.Dreamspace, v => s.Dreamspace = v);
        Add("Cyberspace", s.Cyberspace, v => s.Cyberspace = v);
        Add("Singularity", s.Singularity, v => s.Singularity = v);

        layout.Controls.Add(new Label { Text = "Behavior", Font = new Font(Font, FontStyle.Bold), AutoSize = true, Margin = new Padding(0, 14, 0, 0) });
        Add("Launch Roblox automatically (readable links)", s.AutoLaunch, v => s.AutoLaunch = v);
        Add("Auto-click the “Click to Join Server” button", s.AutoClickJoinButton, v => s.AutoClickJoinButton = v);
        Add("Play a sound on detect", s.PlaySound, v => s.PlaySound = v);
        Add("Show a notification on detect", s.NotifyOnDetect, v => s.NotifyOnDetect = v);

        layout.Controls.Add(new Label
        {
            Text = "Hotkeys:  Ctrl+Alt+P pause · Ctrl+Alt+J join last · Ctrl+Alt+K click newest",
            AutoSize = true, ForeColor = SystemColors.GrayText, Margin = new Padding(0, 14, 0, 0), MaximumSize = new Size(320, 0)
        });

        var ok = new Button { Text = "Save", DialogResult = DialogResult.OK, Margin = new Padding(0, 14, 0, 0) };
        layout.Controls.Add(ok);
        AcceptButton = ok;
        Controls.Add(layout);
    }
}
