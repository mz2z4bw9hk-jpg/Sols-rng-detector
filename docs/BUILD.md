# Build Instructions

## Requirements

| Tool | Version |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 16.0 or later (Swift 6 toolchain) |

No third-party dependencies — the project builds with a fresh Xcode install.

## Build & run (Xcode)

```bash
open BiomeAlertPro.xcodeproj
```

Select the **BiomeAlertPro** scheme → **⌘R**.

Signing is set to *Automatic*. For local development no Apple Developer team
is required — Xcode signs to run locally. If Xcode prompts, pick your
personal team under *Signing & Capabilities*.

## Build & run (command line)

```bash
# Debug build
xcodebuild -project BiomeAlertPro.xcodeproj \
           -scheme BiomeAlertPro \
           -configuration Debug build

# Release archive-style build into ./build
xcodebuild -project BiomeAlertPro.xcodeproj \
           -scheme BiomeAlertPro \
           -configuration Release \
           -derivedDataPath build build

open build/Build/Products/Release/BiomeAlertPro.app
```

## Project layout

```
BiomeAlertPro.xcodeproj/        Xcode 16 project (filesystem-synchronized groups)
BiomeAlertPro/
  App/                          @main entry, AppDelegate, AppEnvironment (DI root)
  Models/                       Codable value types (alerts, keywords, links, logs…)
  Services/                     All engines & I/O (detection, network, storage…)
  ViewModels/                   MVVM view models for interactive screens
  Views/                        SwiftUI screens + reusable components
  Resources/Assets.xcassets     App icon, accent color
  Info.plist                    URL scheme (biomealertpro://) for OAuth callback
  BiomeAlertPro.entitlements    Sandbox + network entitlements
docs/                           Setup, build, architecture documentation
```

The project uses Xcode 16's *filesystem-synchronized* groups: any Swift file
added under `BiomeAlertPro/` is picked up automatically — no pbxproj surgery.

## Configuration knobs

| Setting | Where | Default |
|---|---|---|
| Bundle ID | target build settings | `com.biomealert.BiomeAlertPro` |
| Deployment target | project build settings | macOS 14.0 |
| Swift language mode | `SWIFT_VERSION` | 6.0 (strict concurrency) |
| Sandbox / Hardened Runtime | entitlements + build settings | enabled |

## Troubleshooting

- **Notifications don't appear** — System Settings → Notifications → Biome
  Alert Pro → Allow. Development-signed builds occasionally need one
  relaunch after granting permission.
- **"Port already in use" in the listener status** — change the port in
  Sources and click Apply, or free the port.
- **Roblox opens the game page instead of the server** — install the Roblox
  macOS app so `roblox://` deep links resolve; the browser is only a
  fallback.
- **OAuth bounce-back does nothing** — verify the redirect URI
  `biomealertpro://oauth/callback` is registered in your Discord application
  exactly, and that you launched the app at least once so macOS registered
  the URL scheme.
- **Gateway shows "Invalid bot token"** — regenerate the token in the
  Developer Portal and reconnect; ensure *Message Content Intent* is enabled.
