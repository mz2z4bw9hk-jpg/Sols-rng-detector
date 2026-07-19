using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace BiomeAlertPro;

public enum Biome { Glitched, Dreamspace, Cyberspace, Singularity }

public static class BiomeInfo
{
    public static bool IsRare(this Biome b) => b is Biome.Glitched or Biome.Dreamspace;

    public static string Display(this Biome b) => b switch
    {
        Biome.Glitched => "Glitched",
        Biome.Dreamspace => "Dreamspace",
        Biome.Cyberspace => "Cyberspace",
        Biome.Singularity => "Singularity",
        _ => b.ToString()
    };

    /// Normalized keywords that indicate each biome (mirrors the macOS defaults).
    public static IReadOnlyDictionary<Biome, string[]> Keywords { get; } = new Dictionary<Biome, string[]>
    {
        [Biome.Glitched] = new[] { "glitched", "glitch", "glitched biome", "glitched ps" },
        [Biome.Dreamspace] = new[] { "dreamspace", "dream ps", "dream", "drm" },
        [Biome.Cyberspace] = new[] { "cyberspace", "cyber ps", "cspace", "cyber" },
        [Biome.Singularity] = new[] { "singularity", "sing" },
    };
}

/// A validated Roblox join target extracted from text.
public sealed record RobloxLink(string Original, string? PlaceId, string? LinkCode)
{
    /// Direct deep link that launches Roblox into the private server, if possible.
    public string? DeepLink =>
        PlaceId is not null && LinkCode is not null
            ? $"roblox://placeId={PlaceId}&linkCode={LinkCode}"
            : null;

    public string LaunchTarget => DeepLink ?? Original;

    public string DedupeKey => LinkCode is not null ? "code:" + LinkCode : "url:" + Original.ToLowerInvariant();
}

public sealed record Detection(Biome? Biome, IReadOnlyList<RobloxLink> Links, string MatchedContext);

/// Pure keyword + Roblox-link detection, ported from the macOS engine.
public static class DetectionEngine
{
    public static string Normalize(string text)
    {
        string lowered = text.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(lowered.Length);
        foreach (char c in lowered)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(c);
        return sb.ToString();
    }

    public static Biome? ClassifyBiome(string text, IEnumerable<Biome> enabled)
    {
        string n = Normalize(text);
        foreach (var biome in enabled)
            foreach (var kw in BiomeInfo.Keywords[biome])
                if (n.Contains(kw))
                    return biome;
        return null;
    }

    // Strict code formats so OCR-glued words can't corrupt a link → 404.
    private static readonly Regex PrivateServer = new(
        @"https?://(?:www\.|web\.)?roblox\.com/games/(\d{1,15})[^\s<>""']*?[?&]privateServerLinkCode=(\d{10,32})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex ShareLink = new(
        @"https?://(?:www\.)?roblox\.com/share\?[^\s<>""']*?code=([0-9a-fA-F]{32})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex AnyUrl = new(
        @"https?://[^\s<>""']+", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex UrlPlaceId = new(
        @"[?&]placeId=(\d{1,15})", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex UrlLinkCode = new(
        @"[?&]link_?code=(\d{10,32})", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex DeepLinkRx = new(
        @"roblox://[^\s<>""']+", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// Extracts joinable Roblox links, preferring ones we can deep-link.
    public static List<RobloxLink> DetectLinks(string text)
    {
        var found = new List<RobloxLink>();
        var seen = new HashSet<string>();
        void Add(RobloxLink l) { if (seen.Add(l.DedupeKey)) found.Add(l); }

        // 1. Private server links.
        foreach (Match m in PrivateServer.Matches(text))
            Add(new RobloxLink(Clean(m.Value), m.Groups[1].Value, m.Groups[2].Value));

        // 2. Join-helper / redirect URLs carrying placeId + link_code (the URL
        //    behind a "Click to Join Server" hyperlink).
        foreach (Match m in AnyUrl.Matches(text))
        {
            string url = Clean(m.Value);
            string low = url.ToLowerInvariant();
            if (!low.Contains("placeid=")) continue;
            if (!low.Contains("link_code=") && !low.Contains("linkcode=")) continue;
            if (low.Contains("roblox.com/games/")) continue;
            var p = UrlPlaceId.Match(url);
            var c = UrlLinkCode.Match(url);
            if (p.Success && c.Success)
                Add(new RobloxLink(url, p.Groups[1].Value, c.Groups[1].Value));
        }

        // 3. roblox:// deep links.
        foreach (Match m in DeepLinkRx.Matches(text))
        {
            string url = Clean(m.Value);
            var p = UrlPlaceId.Match(url);
            var c = Regex.Match(url, @"linkCode=(\d{10,32})", RegexOptions.IgnoreCase);
            Add(new RobloxLink(url, p.Success ? p.Groups[1].Value : null, c.Success ? c.Groups[1].Value : null));
        }

        // 4. Share links (server type).
        foreach (Match m in ShareLink.Matches(text))
            Add(new RobloxLink(Clean(m.Value), null, m.Groups[1].Value));

        var pruned = PruneTruncated(found);
        // Deep-linkable first.
        pruned.Sort((a, b) => (a.DeepLink is null ? 1 : 0) - (b.DeepLink is null ? 1 : 0));
        return pruned;
    }

    private static List<RobloxLink> PruneTruncated(List<RobloxLink> links) =>
        links.Where(l =>
        {
            if (l.LinkCode is null) return true;
            return !links.Any(o => o.LinkCode is not null && o.LinkCode != l.LinkCode
                                   && o.LinkCode.Length > l.LinkCode.Length
                                   && o.LinkCode.StartsWith(l.LinkCode));
        }).ToList();

    private static string Clean(string raw)
    {
        int end = raw.Length;
        while (end > 0 && ")]>.,;:!\"'".IndexOf(raw[end - 1]) >= 0) end--;
        return raw[..end];
    }
}
