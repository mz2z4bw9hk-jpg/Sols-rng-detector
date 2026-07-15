# Biome Alert Pro

A production-quality, native macOS companion app for **Sol's RNG** players.
Biome Alert Pro receives biome alerts through **officially supported Discord
integrations**, detects rare biome notifications with an intelligent keyword
engine, and **launches Roblox immediately** when a supported private server
link arrives.

Built with **Swift 6**, **SwiftUI**, and modern Apple frameworks. Sandboxed,
Hardened Runtime, Keychain-backed secrets, and designed to run continuously in
the background at **< 2 % CPU and < 100 MB memory**.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI-purple)

---

## ✅ Compliance first

Biome Alert Pro uses **only official Discord authentication and APIs**:

| Integration | What it's used for | Official mechanism |
|---|---|---|
| **Discord OAuth2 (+PKCE)** | "Sign in with Discord" identity | `oauth2/authorize` + `identify` scope |
| **Discord incoming webhooks** | Outbound: forward alerts / test deliveries into your channels | `POST /api/webhooks/{id}/{token}` |
| **Discord bot Gateway** | Inbound: receive channel messages via *your own bot* | Gateway v10 (identify, heartbeat, resume) |
| **Local webhook listener** | Inbound: accept Discord-webhook-style JSON from your own forwarders | Local HTTP endpoint on 127.0.0.1 |
| **Screen Watcher** | Inbound: OCR your *own* Discord window locally (for servers you can't add a bot to) | ScreenCaptureKit + Vision, fully on-device, read-only — touches no Discord API |

**No user tokens. No self-botting. No reverse-engineered endpoints.**
(Note: Discord webhooks by design only *send into* Discord — to *receive*
messages the official path is a bot, which this app supports natively.)

## Features

- **Dashboard** — monitoring status, connection states, alerts today, rare
  biomes detected, launch count, last detection, detection latency, live
  CPU/memory usage, app version.
- **Sources** — Discord OAuth sign-in, official bot (Gateway) connection with
  automatic reconnect + exponential backoff, a local webhook listener
  endpoint with optional shared secret, and a Screen Watcher that OCRs your
  own Discord window on-device (ScreenCaptureKit + Vision) for alert servers
  where you can't invite a bot.
- **Per-biome auto-launch** — choose exactly which biomes (Glitched,
  Dreamspace, Cyberspace, Singularity) are allowed to launch Roblox
  automatically.
- **Webhook manager** — unlimited outbound Discord webhooks: add, edit,
  enable/disable, delete, validate, test, delivery status, retries with
  exponential backoff, Keychain storage.
- **Keyword engine** — ships with the full Sol's RNG vocabulary (Glitched,
  Dreamspace, Cyberspace, Singularity + action words). Case-insensitive,
  whole-word, partial, and regex matching; Unicode normalization; fuzzy
  matching for small typos; confidence scoring; duplicate suppression; fully
  user-editable with import/export and restore-defaults.
- **Roblox link detection** — private server links, share links, game URLs,
  `roblox://` deep links, and job IDs, with strict validation to prevent
  false positives.
- **Instant launch** — opens Roblox via deep link (browser fallback),
  configurable delay, duplicate-launch cooldown, launch counting, and
  latency measurement.
- **Notifications** — native macOS notifications with biome, source, sender,
  latency, and a **Launch Roblox** quick action; configurable alert sound.
- **Alert history** — searchable, filterable, sortable; CSV/JSON export;
  per-row join button; delete/clear.
- **Structured logs** — startup/shutdown, connections, webhook activity,
  detection, launches, errors, performance; level filtering and export.
- **Menu bar mode** — live stats + controls in the menu bar, optional
  Dock-icon-free operation, launch at login (SMAppService).
- Dark Mode, Light Mode, Retina, smooth animations, HIG-aligned layout.

## Quick start

1. **Requirements:** macOS 14+, Xcode 16+ (Swift 6 toolchain).
2. Open `BiomeAlertPro.xcodeproj` in Xcode.
3. Select the **BiomeAlertPro** scheme and press **⌘R**.

Then connect a source (see [docs/SETUP.md](docs/SETUP.md)):

- **Fastest:** keep the local webhook listener on (default, port 8787) and
  POST Discord-style JSON at it, or
- **Full Discord integration:** create a bot in the Discord Developer Portal,
  enable the *Message Content* intent, invite it to your alert server, and
  paste its token in **Sources**.

Press **Test Alert** on the Dashboard to exercise the entire pipeline
(detection → notification → sound → launch) end to end.

## Documentation

- [docs/SETUP.md](docs/SETUP.md) — Discord OAuth app, bot creation, webhook
  configuration, listener forwarders.
- [docs/BUILD.md](docs/BUILD.md) — build, run, archive, and troubleshooting.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — MVVM structure, services,
  concurrency model, data flow.

## Dependencies

**None.** 100 % first-party Apple frameworks: SwiftUI, AppKit, Combine,
Foundation, Network, URLSession, UserNotifications, CryptoKit, Security
(Keychain), ServiceManagement, UniformTypeIdentifiers, os.log.
Swift Package Manager is supported out of the box if you want to add packages
later — the project intentionally ships with an empty dependency list.

## Security notes

- All secrets (webhook URLs, OAuth tokens, bot token, listener shared secret)
  are stored in the **macOS Keychain** — never in files, never in logs.
- The webhook listener binds to **127.0.0.1** unless you explicitly allow LAN
  access, size-caps request bodies, and supports a constant-time-compared
  shared secret header.
- App Sandbox + Hardened Runtime are enabled; network entitlements are the
  minimum required (client + server).
- Incoming payloads are strictly validated; malformed JSON is rejected.

## Disclaimer

Biome Alert Pro is a fan-made utility. It is not affiliated with Discord
Inc., Roblox Corporation, or the creators of Sol's RNG. Use it with alert
servers you are a member of and follow each platform's Terms of Service.
