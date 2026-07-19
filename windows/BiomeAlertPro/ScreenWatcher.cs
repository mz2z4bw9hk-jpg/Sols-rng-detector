using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Text.RegularExpressions;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace BiomeAlertPro;

/// Captures the Discord window, OCRs it with Windows' built-in engine, detects
/// biomes/links, and joins (deep-link launch or clicking the Join button).
public sealed class ScreenWatcher : IDisposable
{
    private readonly AppSettings _settings;
    private readonly Action<string> _log;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly OcrEngine? _ocr;

    private readonly HashSet<string> _seenLinks = new();
    private readonly HashSet<string> _clickedIds = new();
    private bool _primed;
    private bool _busy;

    public bool Running { get; private set; }
    public RobloxLink? LastLink { get; private set; }
    public event Action<Biome>? BiomeJoined;

    private static readonly Regex MessageId = new(@"ID:\s*(\d{6,})", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public ScreenWatcher(AppSettings settings, Action<string> log)
    {
        _settings = settings;
        _log = log;
        _ocr = OcrEngine.TryCreateFromUserProfileLanguages() ?? OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en-US"));
        _timer = new System.Windows.Forms.Timer { Interval = 400 }; // ~2.5 checks/sec
        _timer.Tick += async (_, _) => await TickAsync();
    }

    public void Start()
    {
        if (_ocr is null) { _log("Windows OCR is unavailable — install the English language pack."); return; }
        _primed = false;
        Running = true;
        _timer.Start();
        _log("Screen watcher started.");
    }

    public void Stop()
    {
        Running = false;
        _timer.Stop();
        _log("Screen watcher stopped.");
    }

    /// Manual hotkey: click the newest targeted button on the next scan.
    public void RequestManualClick() => _forceClick = true;
    private bool _forceClick;

    private async Task TickAsync()
    {
        if (!Running || _busy || _ocr is null) return;
        _busy = true;
        try
        {
            IntPtr hwnd = Native.FindDiscordWindow();
            if (hwnd == IntPtr.Zero) return;

            using Bitmap? bmp = Native.CaptureWindow(hwnd, out Native.RECT rect);
            if (bmp is null) return;

            OcrResult result = await RunOcrAsync(bmp);
            HandleOcr(result, hwnd, rect);
        }
        catch (Exception ex) { _log("Scan error: " + ex.Message); }
        finally { _busy = false; }
    }

    private async Task<OcrResult> RunOcrAsync(Bitmap bmp)
    {
        using var ms = new MemoryStream();
        bmp.Save(ms, ImageFormat.Bmp);
        ms.Position = 0;
        using var ras = new InMemoryRandomAccessStream();
        using (var dw = new DataWriter(ras))
        {
            dw.WriteBytes(ms.ToArray());
            await dw.StoreAsync();
            await dw.FlushAsync();
            dw.DetachStream();
        }
        ras.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(ras);
        using var software = await decoder.GetSoftwareBitmapAsync();
        return await _ocr!.RecognizeAsync(software);
    }

    private void HandleOcr(OcrResult result, IntPtr hwnd, Native.RECT rect)
    {
        string fullText = string.Join("\n", result.Lines.Select(l => l.Text));
        string condensed = new string(fullText.Where(c => !char.IsWhiteSpace(c)).ToArray());
        var enabled = _settings.EnabledBiomes().ToList();
        if (enabled.Count == 0) return;

        // --- Link-launch path (readable links) ---
        if (!_settings.AutoClickJoinButton)
        {
            var links = DetectionEngine.DetectLinks(fullText)
                .Concat(DetectionEngine.DetectLinks(condensed))
                .GroupBy(l => l.DedupeKey).Select(g => g.First()).ToList();

            if (!_primed) { _primed = true; foreach (var l in links) _seenLinks.Add(l.DedupeKey);
                _log($"Primed: ignoring {links.Count} link(s) already on screen."); return; }

            foreach (var link in links.Where(l => !_seenLinks.Contains(l.DedupeKey)))
            {
                _seenLinks.Add(link.DedupeKey);
                var biome = DetectionEngine.ClassifyBiome(fullText, enabled);
                if (biome is null || !_settings.Enabled(biome.Value)) continue;
                LastLink = link;
                Launch(link, biome.Value);
                return;
            }
            return;
        }

        // --- Click path (join link hidden behind a button) ---
        // Build (id, y) from lines that contain a visible "ID: <n>" (used to
        // dedupe so each alert is clicked once).
        var idList = new List<(string Id, double Y)>();
        foreach (var line in result.Lines)
        {
            var m = MessageId.Match(line.Text);
            if (m.Success && line.Words.Count > 0)
                idList.Add((m.Groups[1].Value, line.Words.Average(w => w.BoundingRect.Y + w.BoundingRect.Height / 2)));
        }

        if (!_primed)
        {
            _primed = true;
            foreach (var id in idList) _clickedIds.Add(id.Id);
            _log($"Primed: ignoring {idList.Count} message(s) already on screen; only new drops get clicked.");
            return;
        }

        // Join buttons = words forming "Click to Join Server".
        var buttonLines = result.Lines
            .Where(l => l.Text.ToLowerInvariant().Contains("join server") || l.Text.ToLowerInvariant().Contains("click to join"))
            .ToList();
        if (buttonLines.Count == 0) return;

        bool manual = _forceClick; _forceClick = false;

        // Newest is lowest on screen (largest Y).
        foreach (var line in buttonLines.OrderByDescending(l => l.Words.Count > 0 ? l.Words.Average(w => w.BoundingRect.Y) : 0))
        {
            if (line.Words.Count == 0) continue;
            double cx = line.Words.Average(w => w.BoundingRect.X + w.BoundingRect.Width / 2);
            double cy = line.Words.Average(w => w.BoundingRect.Y + w.BoundingRect.Height / 2);

            string key = idList.Count > 0
                ? idList.OrderBy(i => Math.Abs(i.Y - cy)).First().Id
                : "pos:" + ((int)cy);
            if (!manual && _clickedIds.Contains(key)) continue;

            // Classify by text near the button (its message header).
            string context = string.Join(" ", result.Lines
                .Where(l => l.Words.Count > 0 && Math.Abs(l.Words.Average(w => w.BoundingRect.Y + w.BoundingRect.Height / 2) - cy) < 180)
                .Select(l => l.Text));
            var biome = DetectionEngine.ClassifyBiome(context, enabled);
            if (biome is null || !_settings.Enabled(biome.Value)) continue;

            _clickedIds.Add(key);

            int screenX = rect.Left + (int)cx;
            int screenY = rect.Top + (int)cy;

            if (!Native.IsForeground(hwnd))
            {
                Native.FocusWindow(hwnd);
                System.Threading.Thread.Sleep(120);
            }
            _log($"{(manual ? "Manually clicking" : "Auto-clicking")} Join for {biome.Value.Display()} at ({screenX},{screenY})");
            Native.ClickAt(screenX, screenY);
            BiomeJoined?.Invoke(biome.Value);
            return;
        }
    }

    private void Launch(RobloxLink link, Biome biome)
    {
        if (!_settings.AutoLaunch) { _log($"{biome.Display()} detected (auto-launch off)."); return; }
        try
        {
            Process.Start(new ProcessStartInfo { FileName = link.LaunchTarget, UseShellExecute = true });
            _log($"Launched Roblox for {biome.Display()}.");
            BiomeJoined?.Invoke(biome);
        }
        catch (Exception ex) { _log("Launch failed: " + ex.Message); }
    }

    public void Dispose() => _timer.Dispose();
}
