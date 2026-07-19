# Biome Alert Pro — Windows

A native Windows port of the core sniping loop: it watches your **Discord
window**, reads it with **Windows' built-in OCR** (no third-party OCR), detects
Glitched / Dreamspace / Cyberspace / Singularity, and either launches Roblox
from the link or **clicks the "Click to Join Server" button** for you.

It builds to a **single self-contained `.exe`** — the person running it needs
**nothing installed** (no .NET runtime, no extra apps). Only *building* it needs
the free .NET SDK.

## What it does

- Finds and captures the Discord window (even when it's behind other windows).
- OCRs it with `Windows.Media.Ocr` (part of Windows 10/11 — always present).
- Detects biomes by keyword and Roblox links, including **join-helper URLs**
  hidden behind a "Click to Join Server" hyperlink → launched as a direct
  `roblox://` deep link.
- **Auto-click mode** for servers where the join link is hidden behind a
  button: it locates the button on screen, brings Discord to the front, and
  clicks it. Only clicks buttons for the biomes you selected.
- Lives in the **system tray**. Double-click the tray icon for Settings.
- Global hotkeys: **Ctrl+Alt+P** pause/resume · **Ctrl+Alt+J** join last link ·
  **Ctrl+Alt+K** click the newest targeted Join button.

## Requirements

- **Windows 10 (1809+) or Windows 11** — for the built-in OCR.
- To **build**: the free [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).
  The English OCR language pack is installed by default; if OCR says it's
  unavailable, add it under *Settings → Time & Language → Language → English →
  Options → Optional features → Enhanced OCR*.

## Build the single .exe

Open a terminal (PowerShell or cmd) in this folder and run:

```powershell
cd BiomeAlertPro
dotnet publish -c Release
```

The finished, standalone program appears at:

```
BiomeAlertPro\bin\Release\net8.0-windows10.0.19041.0\win-x64\publish\BiomeAlertPro.exe
```

Copy that one `BiomeAlertPro.exe` anywhere and run it — it needs nothing else.

## Using it

1. Run `BiomeAlertPro.exe` → it appears in the system tray (bottom-right).
2. Double-click the tray icon → **Settings** → tick the biomes you want and
   choose **Auto-click** (for hidden-link servers) or **Auto-launch** (for
   servers that post readable links).
3. Keep **Discord open** on the alert channel. For auto-click, keep Discord on
   your current screen (it's brought to the front automatically before a click).
4. When a targeted biome drops, it joins — and plays a sound / shows a
   notification.

## Notes & limitations (v1)

- This is a fresh port focused on the core loop; the full macOS UI
  (dashboard/webhooks/history screens) isn't reproduced here.
- OCR can rarely misread a long link code. For servers where you can add a
  Discord **bot**, the bot path (in the macOS app) is byte-exact; on Windows the
  screen-watch + click approach is the equivalent of the macOS Screen Watcher.
- Windows SmartScreen may warn on first run because the .exe is unsigned —
  *More info → Run anyway*. (Code-signing needs a paid certificate.)
- Antivirus may flag the synthetic mouse clicks (auto-clicker behavior); you may
  need to allow it.
