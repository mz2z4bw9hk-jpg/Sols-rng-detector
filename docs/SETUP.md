# Setup Guide

Biome Alert Pro supports three officially-supported ways to get alerts in,
plus outbound webhooks for forwarding. You can use any combination.

---

## 1. Local webhook listener (fastest — zero Discord setup)

The app hosts a tiny HTTP endpoint (default `http://127.0.0.1:8787`) that
accepts **Discord-webhook-style JSON**. Anything you already run that can POST
JSON — a bot you host, a Shortcuts automation, a script — can deliver alerts.

```bash
curl -X POST http://127.0.0.1:8787/alert \
  -H 'Content-Type: application/json' \
  -d '{"content": "GLITCHED biome! https://www.roblox.com/games/15532962292?privateServerLinkCode=abc123XYZ"}'
```

Accepted body shapes:

| Shape | Example |
|---|---|
| Discord *Execute Webhook* JSON | `{"content": "...", "username": "...", "embeds": [{"title": "...", "description": "..."}]}` |
| Simple | `{"message": "..."}` |
| Raw text | `GLITCHED ps https://…` |

Hardening options (Sources → Webhook Listener):

- **Port** — default 8787.
- **Shared secret** — when set, requests must include
  `X-BiomeAlert-Secret: <secret>` (stored in Keychain, compared in constant
  time).
- **LAN access** — off by default; the listener binds to loopback only.
  Enable it in Settings only if another machine on your network forwards
  alerts (requires the port in the `X-BiomeAlert-Secret` setup too, ideally).

## 1.5 Screen Watcher (for alert servers you can't add a bot to)

Community alert servers (biome loggers, etc.) usually won't let you invite
your own bot. The Screen Watcher solves this **without touching Discord's
API at all**: it captures *your own* Discord window with ScreenCaptureKit,
reads it with Apple's on-device Vision OCR, and when a new Roblox
private-server link appears it launches Roblox directly from the extracted
URL. Read-only, 100% local, never automates your Discord account.

1. **Sources → Screen Watcher → Watch my Discord window.**
2. macOS will prompt for **Screen Recording** permission → enable Biome
   Alert Pro in *System Settings → Privacy & Security → Screen Recording* →
   **relaunch the app** (macOS requires it).
3. Keep the Discord app open on the alert channel (e.g. a `dreamspace-logger`
   channel). The window can sit behind other windows — just don't minimize it.
4. Pick which biomes may auto-launch under **Settings → Auto-Launch Biomes**.

**Only-new-links safety (important):**
- **Priming** — when the watcher starts, every link already on screen is
  recorded as "seen" and never joined. Only links that appear *after* it
  starts will launch Roblox. Opening the app on a channel full of old alerts
  will not yank you into a dead server.
- **Freshness limit** — Sources → Screen Watcher → *Ignore links older than*
  (default 3 min) skips links whose "N minutes ago" timestamp is over the
  limit, which also covers scrolling up into old history.
- **Join-once** — each unique link is launched a single time per session and
  never re-clicked, even while it stays on screen.

Notes:
- Only Discord app windows are captured — never the whole screen.
- Frames are OCR'd only when the window content changes (~2 checks/second),
  so detection typically lands within a second of the message appearing.
- The watcher reads the channel you're *looking at*. To cover several
  channels at once (glitched-snipes, dreamspace-snipes, …) without switching,
  use the bot below — it sees every channel simultaneously.
- Long private-server codes are OCR'd at 2× resolution with language
  correction disabled; wrapped URLs are reassembled automatically. OCR can
  still occasionally misread a character — the bot/webhook sources are
  byte-exact when you have the option.
- On macOS 15+, the system periodically re-confirms screen-capture consent.

## 2. Discord bot (official way to receive Discord messages)

Discord's supported mechanism for reading channel messages is a **bot**:

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
   → **New Application** → give it a name.
2. **Bot** tab → **Reset Token** → copy the bot token.
3. Still on the Bot tab, enable **Message Content Intent** (required to read
   message text) under *Privileged Gateway Intents*.
4. **OAuth2 → URL Generator**: check `bot`, then under Bot Permissions check
   *View Channels* and *Read Message History*. Open the generated URL and
   invite the bot to the server where your biome alerts are posted (you need
   permission in that server, or ask its admin).
5. In Biome Alert Pro → **Sources → Discord Bot**, paste the token and click
   **Connect Bot**. The token goes straight into the macOS Keychain.

The app connects to the official Gateway (v10), heartbeats, resumes dropped
sessions, and reconnects automatically with exponential backoff. Messages
from every channel the bot can see flow through the keyword engine.

**Watching multiple channels at once:** the bot sees *all* channels it has
access to simultaneously — no switching, no clicking. In **Sources → Discord
Bot → Channels to watch**, list the channel names you care about
(`glitched-snipes, dreamspace-snipes, cyberspace-snipes, singularity-snipes`)
to act only on those; leave it blank to watch every channel. Each alert is
tagged with the channel it came from in **Alert History** and in the
notification, and only-new/join-once dedupe applies here too (by Discord
message ID), so old messages are never re-joined.

> Only add the bot to servers whose owners are fine with it — the same rule
> as any Discord bot.

## 3. Sign in with Discord (OAuth2)

Optional — gives the app your Discord identity for the dashboard, using the
official OAuth2 authorization-code flow with PKCE and only the `identify`
scope. The app cannot read messages with this — that's what bots are for.

1. In the [Developer Portal](https://discord.com/developers/applications),
   open your application → **OAuth2**.
2. Add a redirect URI: `biomealertpro://oauth/callback`
3. Copy the **Client ID** into **Sources → Discord Account** and click
   **Sign in with Discord**. Your browser opens; approve; you're bounced back
   to the app.
4. Public clients work with PKCE alone. If your app is configured as
   confidential, paste the client secret too (stored in Keychain).

## 4. Outbound webhooks (forwarding)

To re-broadcast detected alerts into your own Discord channels:

1. In Discord: channel → **Edit Channel → Integrations → Webhooks → New
   Webhook** → *Copy Webhook URL*.
2. In Biome Alert Pro → **Webhooks → +**, paste the URL. It is validated
   structurally, verified live with a GET, and stored in the Keychain.
3. **Test** sends a test message. Deliveries retry with exponential backoff
   and honor Discord rate limits.
4. Toggle **Forward detected alerts to all enabled webhooks** at the bottom
   of the Webhooks screen.
5. Optionally enable **Ping @everyone in forwarded alerts**. The mention only
   fires in *your* server (where the webhook posts and where you have
   permission to mention everyone) — it never pings the server you're
   watching. Requires the forwarding toggle to be on.

## 5. Roblox launching

- With the [Roblox macOS app](https://www.roblox.com/download) installed,
  private server links open **directly into the server** via `roblox://`
  deep links.
- Without it, links open in your default browser as a fallback.
- Tune behavior in **Settings → Roblox Launch**: automatic launch on/off,
  launch delay, duplicate-launch cooldown, rare-biomes-only mode.

## 5.5 Power features (Settings)

- **Global hotkeys** — enable in Settings → Hotkeys. Work anywhere, even while
  Roblox/Discord is focused:
  - **⌥⌘J** — join the last detected link (your instant manual fallback if OCR
    misreads a code).
  - **⌥⌘P** — pause / resume monitoring.
  The menu-bar panel also has a **Join Last Link** button.
- **Per-biome sounds** — Settings → Notifications & Sound → “Use a different
  sound per biome.” Hear whether it's Glitched vs Singularity without looking.
- **Blocklist words** — Settings → Detection. Any message containing a blocked
  word (default: fake, expired, closed, patched, scam, full, ended, over) is
  ignored, so a dead-server link never launches.
- **Faster screen watcher** — the watcher now samples ~5×/second and OCRs only
  the message area (skipping Discord's sidebar) for lower join latency.

## 6. Recommended first run

1. Launch the app → grant notification permission.
2. Dashboard → **Test Alert** — you should see a notification, hear the
   sound, and watch a (test) private-server launch attempt appear in
   **Alert History**.
3. Connect your real source and you're done. The app is happy living in the
   menu bar (Settings → *Menu bar only*).
