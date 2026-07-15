# Architecture

Biome Alert Pro is a Swift 6 / SwiftUI app structured around **MVVM +
dependency injection + protocol-oriented services**, with strict concurrency
(Swift 6 language mode) enforced at compile time.

## High-level data flow

```
   ┌────────────────────┐   ┌─────────────────────┐
   │ WebhookListener    │   │ DiscordGateway      │
   │ (NWListener HTTP,  │   │ (official bot WS,   │
   │  loopback)         │   │  auto-reconnect)    │
   └─────────┬──────────┘   └──────────┬──────────┘
             │ AsyncStream<IncomingEvent>│
             └───────────┬──────────────┘
                         ▼
               ┌───────────────────┐
               │   AlertPipeline   │  actor (off the main thread)
               │  • dedupe (ID +   │
               │    content hash)  │
               │  • KeywordEngine  │
               │  • LinkDetector   │
               │  • confidence     │
               └─────────┬─────────┘
                         ▼ @MainActor
               ┌───────────────────┐
               │  AppEnvironment   │  composition root / DI container
               │  deliver(record)  │
               └┬────┬────┬────┬───┘
                ▼    ▼    ▼    ▼
          History Stats Notify RobloxLauncher ─▶ roblox:// deep link
                │              │
                ▼              ▼
          WebhookStore.broadcast (optional forwarding, retry + backoff)
```

## Layers

### Models (`Models/`)
Pure `Codable`/`Sendable` value types: `Keyword`, `AlertRecord`,
`RobloxLink`, `IncomingEvent`, `LogEntry`, `WebhookConfig`, Discord DTOs.
No behavior beyond formatting helpers — trivially unit-testable.

### Services (`Services/`)
Each service has a single responsibility; the ones with seams for testing are
protocol-typed:

| Protocol | Production type | Purpose |
|---|---|---|
| `SecretStoring` | `KeychainService` (+ `InMemorySecretStore` for tests) | Keychain generic passwords |
| `KeywordMatching` | `KeywordEngine` | normalization, whole-word/partial/regex, fuzzy, scoring |
| `LinkDetecting` | `RobloxLinkDetector` | strict Roblox URL/job-ID parsing |
| `WebhookSending` | `DiscordWebhookClient` | outbound webhooks, retries, rate limits |

Stateful stores (`SettingsStore`, `KeywordStore`, `HistoryStore`,
`WebhookStore`, `StatsStore`, `LogStore`) are `@MainActor ObservableObject`s
with debounced JSON persistence in Application Support.

### Concurrency model

- **`@MainActor`** — every store, view model, and UI-facing service.
  Global-actor isolation makes them implicitly `Sendable`.
- **actors** — `AlertPipeline` (detection), `DiscordGatewayService`
  (WebSocket protocol state), `DiscordWebhookClient` (delivery).
- **`@unchecked Sendable` + serial queue** — `WebhookListenerService` wraps
  the Network framework, whose types aren't Sendable; all mutable state is
  confined to one `DispatchQueue`.
- **Bridging** — sources expose `AsyncStream<IncomingEvent>`; callbacks that
  cross threads are `@Sendable` closures that hop with `Task { @MainActor in … }`.
- **No timers, no polling loops on the main thread** — periodic work
  (performance sampling, heartbeats) uses structured `Task.sleep` loops.

### ViewModels (`ViewModels/`)
Screen-scoped `@MainActor ObservableObject`s that own form state, validation,
and user-intent methods (`WebhooksViewModel`, `KeywordsViewModel`,
`HistoryViewModel`, `SourcesViewModel`). Read-mostly screens (Dashboard,
Logs, About) bind the observable stores directly.

### Views (`Views/`)
`NavigationSplitView` shell with eight destinations, plus a `MenuBarExtra`
scene. Reusable pieces live in `Views/Components`. Views contain zero
business logic.

## Key design decisions

- **AppEnvironment as composition root** — all services are constructed and
  wired in one place; anything can be swapped for a test double via
  initializer injection.
- **Detection off the main thread** — the pipeline actor snapshots settings +
  keywords per event (`DetectionConfiguration`, a `Sendable` value) so
  matching never touches main-actor state mid-flight.
- **Duplicate suppression at two levels** — event level (upstream ID +
  normalized-content SHA-256 with TTL) and launch level (per-server cooldown
  in `RobloxLauncher`).
- **Secrets never persist outside the Keychain** — `WebhookConfig` stores
  only metadata; URLs/tokens resolve through `SecretStoring` at use time,
  and log messages never interpolate secret values.
- **Latency accounting** — `IncomingEvent.receivedAt` is stamped at the
  transport edge; detection latency is measured to pipeline completion and
  displayed per alert and as a rolling average.

## Performance

- Event-driven end to end: zero polling, near-zero idle CPU.
- Performance monitor samples CPU (via `clock_gettime_nsec_np` deltas) and
  memory footprint (via `proc_pid_rusage`) every 5 s and warns when the
  configurable CPU target (default 2 %) is exceeded.
- History and logs are capped (configurable) and persisted with debounce to
  avoid disk churn.

## Testing strategy

The seams are in place for a unit-test target (add one in Xcode: File → New →
Target → Unit Testing Bundle):

- `KeywordEngine` and `RobloxLinkDetector` are pure functions over inputs.
- `WebhookListenerService.parseEvent` is a static, IO-free parser.
- Stores accept custom file URLs and `InMemorySecretStore`.
- `AlertPipeline` accepts mock `KeywordMatching`/`LinkDetecting`.
