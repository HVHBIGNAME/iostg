# Whitegram 8.1.1 reference review

Updated **2026-11-06** for the Telegram **13.1.2 / build 34654** source candidate.
This compares the two supplied reference IPAs and relates their observed changes
to the current client sources. Reference code was inspected statically; original
UI behavior, service responses and runtime policies were not exercised.

## Artifact identity and method

| Reference | SHA-256 |
| --- | --- |
| `Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa` | `5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf` |
| `Whitegram 8.1.1 (13.1.1) [tg@thewhitegram].ipa` | `2d514fb03b56c37a372b5c26ac4f973e8e57b28bd13d5c7d943c556afe658e03` |
| 3.2 `TelegramCoreFramework` | `9908ba0fcf3782f6f7da9a3b4f82b941cc95c952ba1b631cb33451747e96e198` |
| 3.2 `TelegramUIFramework` | `7f64950144cc75631ceb9cc9365cd4d802d583e5315ee63498829a1c72cb3ac3` |
| 8.1.1 `TelegramCoreFramework` | `5037c126bc81fdd0eeaa03c18a99dfe0bd73f05e974f6696cb83454d19e67ddf` |
| 8.1.1 `TelegramUIFramework` | `39be3c237fff5f7061cb9ab0ce78ff2f88a8eb1252586b0642508f8b9ee7bfcf` |

The 8.1.1 carrier contains `Payload/Whitegram.app`, bundle identifier
`ph.telegra.Telegraph`, version `13.1.1`, build `81`. Framework member paths are
`Payload/Whitegram.app/Frameworks/<name>.framework/<name>`.

The local `whitegram-rebuild/wgtool` parser verified thin, unencrypted ARM64 images,
recovered custom Swift reflection records, enumerated exported names and `wg_*`
literals, and hashed recognized embedded source strings. Duplicate type-name
pairings and reflection parsing issues were rejected. Names and reflected fields
are structural observations; policy meanings inferred from them require further
function-level or runtime verification.

The full local inventory and comparison scripts are retained in
`C:\Users\Pisun4ik\AppData\Local\Temp\opencode\`:
`whitegram-reference-comparison-811.json`, `compare-whitegram-811-features.py`
and `summarize-whitegram-811.py`. The identities and relevant observations are
preserved below so the findings are tied to exact reference bytes.

## Observed changes from 3.2

| Inventory | 3.2 | 8.1.1 |
| --- | ---: | ---: |
| Recovered custom Core types | 90 | 91 |
| Recovered custom UI types | 372 | 378 |
| `WhitegramEntry` reflected cases | 340 | 342 |
| `WhitegramSettingsState` reflected fields | 252 | 253 |
| Recognized embedded JS/HTML strings in UI | 12 | 12 |

All 12 recognized embedded sources match the earlier reference's SHA-256 values;
no changed or new source was found in that inventory. This does not establish
native-host equivalence or discover dynamically downloaded runtime assets.

| Finding | Observed metadata in 8.1.1 |
| --- | --- |
| Message-style time ranges | New Core type `WGMessageStyleTimestampRange`, descriptor `0xc932f4`, fields `from`, `to`. `WGMessageStyle` and `WGMessageStylePeriod` each gain `sentAtRanges`. |
| Diagnostics | New UI types `WhitegramDiagnosticsConsent`, `WhitegramDiagnosticsOutbox`, `WhitegramDiagnosticsReport`, `WhitegramDiagnosticsUploadCoordinator`, `WhitegramRuntimeDiagnosticsMonitor`. Settings state at `0x5dfc1e4` gains `diagnosticsUploadEnabled`. |
| Additional settings actions | `WhitegramEntry` at `0x5dfc250` gains `clearEntireCache` and `diagnosticsUpload`; `WhitegramSettingsArguments` also gains `clearEntireCache`. |
| Plugin image task | New `WGPluginImageDownload` at `0x5df93b8`, fields `finishLock`, `data`, `session`, `completion`, `finished`. |
| Plugin event state | `WGSDKEvents` at `0x5df8eac` gains `stateLock`; `tracing`, `trace`, `interceptors`, `deferred`, `interceptTrace` are replaced by correspondingly named `*Storage` fields. The earlier `lock` remains. |
| Profile-photo cache | `WGProfilePhotoWallManager` gains `memoryWarningObserver`. `WGProfilePhotosManager` gains `memoryWarningObserver`, `remoteCacheQueue`, `lastRemoteCachePruneAt`. |
| Camera menu | `WGCameraSelectionOverlay` gains `sourcePoint`. Placement/transition behavior remains unverified. |
| Scammer metadata | `WGScammerDatabaseManager` no longer exposes the reflected `snapshotURLBytes` field. This alone does not establish a change in warning behavior or database verification. |

Additional diagnostics records:

- `WhitegramDiagnosticsReport`, `0x5e00350`: `id`, `kind`, `occurredAt`, `metadata`, `payload`.
- `WhitegramDiagnosticsOutbox`, `0x5e00378`: `directory`, `queue`, `maximumReports`,
  `maximumPayloadBytes`, `maximumOutboxBytes`.
- `WhitegramDiagnosticsConsent`, `0x5e003c0`: no reflected stored fields.
- `WhitegramDiagnosticsUploadCoordinator`, `0x5de04d0`: `queue`, `started`,
  `isSending`, `retryAttempt`, `retryScheduled`, `retryGeneration`.

New matched Core literals: `wg_diagnosticsUploadEnabled` and
`wg_runtime_isInBackgroundForDeletedMessageCapture`.
New matched UI literals: `wg_diagnosticsConsentDate`, `wg_diagnosticsDiskSampleBytes`,
`wg_diagnosticsDiskSampleTime`, `wg_diagnosticsLastReportAt_`,
`wg_diagnosticsUploadEnabled`, `wg_profilePhotos_ownedUserIds`.
Literal presence does not prove a key's default, persistence scope or active
consumer. Missing old literals likewise do not prove feature removal.

## Impact on our current implementation

| Area | Current source and remaining work |
| --- | --- |
| Custom-message styles | `hideOthersCustomMessageStyle` still has no operational route. The pure incoming-message gate exists, but the required per-user/chat delivery, cache and renderer do not. The newly observed `sentAtRanges` schema and range precedence/boundaries must be recovered before implementing that pipeline. See [REMAINING_PRESENTATION_PORT.md](REMAINING_PRESENTATION_PORT.md). |
| Diagnostics | We already have MetricKit/service reports, a bounded retry queue, controls and a private receiver in `WhitegramErrorReporter.swift` / `WhitegramDiagnosticsController.swift`. This is our existing `automaticErrorReports` contract. The original 8.1.1 consent key, report schema, runtime monitor, default and upload policy have not been reproduced. See [DIAGNOSTICS_PORT.md](DIAGNOSTICS_PORT.md). |
| Entire-cache action | The new `clearEntireCache` action is absent from our recovered catalog/router. Its original deletion scope and treatment of account data, plugins and media must be traced before adding an equivalent action. Existing Telegram storage controls do not establish equivalence. |
| Plugin image loading | `WhitegramPluginRuntime.prepareImages` handles data-image URLs or package files; `WhitegramPluginUI` renders those bytes and system symbols. Direct HTTP(S) `Image.src` is not supported by this path. Generic plugin HTTP and network-enabled Web HTML already exist. The new original image task's cancellation/completion and response policy remain to be recovered. |
| Event synchronization | Our `WhitegramPluginEventHub` already locks its subscriptions and queued observations; `WhitegramPluginInterception` and services have their own lifetime handling. The new original `stateLock` is a comparison target, not evidence that our events are unlocked. Ordering, interception and deferred-result parity remain open. |
| Profile photos / memory | Our photo endpoints and service cache exist (`WhitegramProfilePhotos.swift`, `WhitegramProfileService.swift`); the service cache is bounded to 128 entries. Original memory-warning eviction, remote-cache pruning and `ownedUserIds` migration are not established by this implementation. |
| Capture while backgrounded | The new deleted-message background literal requires tracing against our history capture rules. No equivalence or new capture policy is inferred from its name. |
| Camera overlay | The new `sourcePoint` suggests a placement-related change. The original layout and our device/camera controls still need a visual/interaction comparison. |

## Existing incomplete transfers

These remain relevant even where the older setting already opens a working screen:

1. **Plugin engine/API coverage:** no bundled TypeScript compiler or running
   Python/Lua/Ruby/Go interpreter payloads; original UI provider slots, tab-bar
   attachment, scheduler/background jobs and raw/deferred MTProto interception
   are incomplete. Existing JavaScript packages, services and WebAssembly in a
   capable host are supported. See [PLUGIN_COMPATIBILITY.md](PLUGIN_COMPATIBILITY.md).
2. **Posts feed:** paginated channel histories, text and attachment actions work;
   media opens the original message rather than providing full inline-media parity.
3. **Classic interface:** legacy tabs/items, plates and composer geometry are
   implemented; the complete original historical layout/transitions are not.
   Both items are included in [BUILD_34652.md](BUILD_34652.md).
4. **Account-private settings:** profiles, switching and scoped import/export work;
   original absent-key/tombstone migration and complete key exclusions remain
   unverified. See [ACCOUNT_SETTINGS_PORT.md](ACCOUNT_SETTINGS_PORT.md).
5. **Badges and profile information:** Black/White window badges are recovered;
   other variants remain missing. Name decoration uses an inline `✦`, not the
   original icon/particle renderer. Registration-date persistent-cache/prefilter
   parity is also incomplete. See [REMAINING_PRESENTATION_PORT.md](REMAINING_PRESENTATION_PORT.md)
   and [BUILD_34646.md](BUILD_34646.md).
6. **Scammer warnings:** the connected profile warning consumes a legacy saved-list
   cache. There is no substantiated signed, current remote-database verifier.
7. **Backgrounds and media lifecycle:** local video/cover controls exist, but
   original visual sampling, all surfaces, portable media transfer and physical
   device interruption/battery behavior are not fully reproduced or verified.
   Older navigation handoff statements that feed/classic are wholly unsupported
   are superseded by the integrated build-34652 implementation.
8. **History, voice/player and network services:** source consumers and tests exist;
   original archive/capture semantics, real-device audio/video workflows and
   authenticated service behavior still require their documented validation.

## Priorities and coverage

First establish a successful native 13.1.2 build using the expanded compiler
diagnostics. Then recover the new action/consent/style contracts and image-task
lifecycle, implement the missing consumers, and exercise them on iOS. Existing
feed/classic, account migration and plugin-engine gaps remain separate work items.

`python -B whitegram/catalog_status.py` currently reports 333 catalog rows:
29 headers, 26 information rows, 4 links, 1 preview, 93 screens, 13 sliders,
166 toggles and **1 unconnected row**. This older extracted catalog is not the
same inventory as either binary's 340/342-case `WhitegramEntry`. In particular,
the two newly observed actions are not included in that one-row remainder.
No overall feature-completion percentage is justified by these routing counts.
