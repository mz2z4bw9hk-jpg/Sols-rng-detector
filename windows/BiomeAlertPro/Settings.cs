using System.Text.Json;

namespace BiomeAlertPro;

/// User settings, persisted as JSON under %AppData%\BiomeAlertPro.
public sealed class AppSettings
{
    public bool AutoLaunch { get; set; } = true;
    public bool AutoClickJoinButton { get; set; } = true;
    public bool PlaySound { get; set; } = true;
    public bool NotifyOnDetect { get; set; } = true;

    // Which biomes to act on.
    public bool Glitched { get; set; } = true;
    public bool Dreamspace { get; set; } = true;
    public bool Cyberspace { get; set; } = true;
    public bool Singularity { get; set; } = true;

    public bool Enabled(Biome b) => b switch
    {
        Biome.Glitched => Glitched,
        Biome.Dreamspace => Dreamspace,
        Biome.Cyberspace => Cyberspace,
        Biome.Singularity => Singularity,
        _ => false
    };

    public IEnumerable<Biome> EnabledBiomes()
    {
        foreach (Biome b in Enum.GetValues<Biome>())
            if (Enabled(b)) yield return b;
    }

    // MARK: Persistence

    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BiomeAlertPro");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch { /* fall through to defaults */ }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* best effort */ }
    }
}
