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

## 5. Roblox launching

- With the [Roblox macOS app](https://www.roblox.com/download) installed,
  private server links open **directly into the server** via `roblox://`
  deep links.
- Without it, links open in your default browser as a fallback.
- Tune behavior in **Settings → Roblox Launch**: automatic launch on/off,
  launch delay, duplicate-launch cooldown, rare-biomes-only mode.

## 6. Recommended first run

1. Launch the app → grant notification permission.
2. Dashboard → **Test Alert** — you should see a notification, hear the
   sound, and watch a (test) private-server launch attempt appear in
   **Alert History**.
3. Connect your real source and you're done. The app is happy living in the
   menu bar (Settings → *Menu bar only*).
