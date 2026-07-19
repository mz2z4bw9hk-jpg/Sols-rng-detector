namespace BiomeAlertPro;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Sets visual styles, text rendering, and DPI mode in one call.
        ApplicationConfiguration.Initialize();

        // The TrayApp is a hidden window that owns the tray icon + watcher.
        using var app = new TrayApp();
        Application.Run(app);
    }
}
