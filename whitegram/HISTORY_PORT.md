# Client history compatibility — Telegram 13.0.0 / Beta 3.2

Source pin: `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838` (`release-13.0.0`).
Pristine files were read with `git show`; the assembled
`C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0`
was used read-only. Patches execute against an in-memory source fixture.

## Parent integration

`HISTORY_RUNTIME_FILES` now also maps these files into TelegramCore `Sources/`:

- `WhitegramHistoryEntities.swift`
- `WhitegramSpyStore.swift`
- `WhitegramSpyRuntime.swift`

Continue installing the entire existing map and invoking `apply_history_patches`.
Add `from spy_patches import apply_spy_patches` and invoke
`apply_spy_patches(source_root)` once. The optional `SPY_RUNTIME_FILES` map contains
the same two spy files; do not install duplicate Swift declarations. Spy and
online-history patchers compose in either order and replay without source writes.
Each patcher validates all of its source edits before committing any writes.

The spy patcher edits accepted presence consumers in `UpdatePeers.swift`, exact
message read-date consumption in `MessageReadStats.swift`, and the existing presence
formatting call in both chat-title implementations and `PeerInfoData.swift`.
It introduces no new build-target dependency: all three UI sites already import
TelegramCore and TelegramStringFormatting, and receive explicit AccountContext IDs.

Parent-owned preferences/catalog/capability routing still needs to expose
`showEditedStrikethrough`, `trackLastOnline` and `saveReadDates`. Suggested capability
classification after spy integration is `settings`, with the spy limitations below.
The existing localization key `s.showEditedStrikethrough` is used by the history
screen; no localization-table edits are required. The spy runtime reads canonical
preferences with original `wg_` fallback. Account logout/registry cleanup and
parent-wide account preference scoping remain parent integration work.

## Verified original evidence

Fresh SHA-256 verification of the supplied IPA:

```text
Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa
5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf
```

Local `wgtool.binary.MachO` inspected original ARM64 bytes without running them.
The recoveries under `whitegram-rebuild/recovered-3.2` / `recovered-3.1.1`
provide complementary symbols/hooks; the following claims use fresh Beta 3.2 bytes.

| Original coordinate | Observation |
| --- | --- |
| TelegramCore `0x21e720`, fallback `0x21e7d0` | `showEditedStrikethrough` getter defaults to true (`mov w19, #1`) |
| TelegramUI `0x189098c`–`0x1890a30` | Checks `showEditedOriginalText`, then `showEditedStrikethrough`, per-chat/bot filters, and nonempty changed original text before entering appended original rendering at `0x1891450` |
| TelegramUI `0x1891948`–`0x1891c20` | Original block builds font/color and attributed-string dictionaries; display switch is independent of persisted edit history |
| TelegramUI `0x24f4bbc` | Status renderer also checks the display switch; exact original status layout is not claimed |
| TelegramCore `0x233aa8`, `0x233b40` → `0x23ec20` | Both spy getters tail-branch to `mov w0, #0; ret`. They are shipped disabled, despite menu/setter symbols |
| TelegramCore `SGReadDatesStore.record` `0x2110c8`, lookup `0x211204` | Original has a peer-to-Int32 timestamp store. No direct record/lookup consumers were found in the inspected core/UI branch inventories |

`tests/test_history_original.py` pins the IPA hash and rechecks these instructions
and online-history schema anchors. Spy behavior below is an evidence-guided client
extension requested by the user, not a claim that disabled Beta 3.2 getters execute it.

## Current implemented behavior

The earlier document was stale. The current runtime already retains deleted cloud
messages in Postbox, filters/changes their inline opacity, persists before-edit text
and entities in native attributes, appends an original-text block, honors own/bot/
per-chat exclusions, and creates local text copies with collision/account checks.
These capabilities remain implemented.

This increment adds:

- **Exact display-only switch:** `showEditedStrikethrough` defaults on; when off,
  the appended original block disappears while capture, native edit history and the
  edited marker continue. The appended original text has single strikethrough;
  current text is unaffected. Existing preview/invoice/story/updating-media guards
  and valid UTF-16/custom-emoji handling remain. The old assembled block upgrades
  once; a drifted strike block is rejected before source writes.
- **Portable entity archives:** optional `entities` use Telegram Codable keys
  (`start`, `end`, `_rawValue`, etc.) and exact Int64 values. Captured descriptors
  include formatting, links, mentions, custom-emoji IDs and formatted dates.
  Import validates the complete batch, 1024-entity cap, lengths, IDs and UTF-16
  boundaries, including split-surrogate rejection. Restoration converts every
  entity batch before its first Postbox mutation and installs native
  `TextEntitiesMessageAttribute`. Old v1 archives still decode without entities.
- **Original deleted-text export:** a separate history-screen action produces the
  recovered nine-field `SGBackedUpMessage` array. Optional author fields are omitted
  when absent, as with Swift Codable. Full peer namespaces/wide IDs are unpacked;
  one non-edit observation per message is exported. Truncated text fails rather
  than becoming a purported complete original backup. Modern export retains richer
  metadata/entities; original export has precisely the original limited schema.
- **Unambiguous replay:** conflicting records with the same canonical archive key
  are rejected before merge; identical duplicates remain idempotent. A late import
  of revision-zero original text no longer displaces a newer captured revision in
  restoration selection. Selection prefers revision within a whole message ID,
  then observation time. Message and optional edit timestamps must be nonnegative.

Modern history still uses account-directory/account-peer registry keys and
`whitegram-history-<accountPeerId>-v1.json`, serialized atomic protected writes,
2000 observations and an 8 MiB cap. Text is bounded to **65536 UTF-8 bytes**, not
the old documented 8 KiB. Native retained messages/edit attributes are not truncated
to this archive bound. Attachment descriptors are bounded to 32 per observation.

## Spy consumers

- `trackLastOnline` stores accepted explicit online/offline contact observations;
  excludes own IDs, bots, noncontacts, min updates rejected by Telegram, and
  privacy-coarse status values. Online uses local observation time; offline uses
  the supplied `wasOnline`. Timestamps are positive, not future, and monotonic.
  Capture writes are queued off the Postbox transaction thread.
- Chat titles/profile presence formatting can use this previously received
  timestamp for a later coarse native presence. Explicit native `.present` values
  and currently active native `.recently` values always win. The UI uses Telegram's
  existing localized last-seen formatting.
  Typing and expiry timers never add timestamps or synthesize online transitions.
- `saveReadDates` stores successful `messages.getOutboxReadDate` replies under
  `(account, peer, cloud message ID)` and supplies that exact cached date to native
  `MessageReadStats`. No extra request or read receipt is introduced. Outbox read
  watermarks are not stamped onto earlier messages, and group participant dates
  are not mislabeled as private-message dates.
- `WhitegramSpy.v1.<accountId>` is bounded to 2000 peers / 2000 exact message read
  dates / 2 MiB. First observed read date wins. Oldest evidence is evicted with
  stable identity tie breaks. Corrupt/foreign archives fail closed and remain intact.

The original shared peer-only `wg_readDates_v1` is deliberately not assigned to
specific messages: it cannot establish a message read date. No original last-online
storage schema was established in the shipped disabled spy implementation.

## Meaningful verification

Executed on this host (2026-10-23):

- History/source/spy suite: **26 passed** with pinned source and no source writes.
  Three optional original-IPA tests skip under the parser-only environment; they
  were separately executed with the recovery venv: **3 passed**, hash verified.
- Online-history/source suite: **6 passed**, including source syntax, replay,
  accepted-merge preservation and late-anchor failure atomicity.
- Native Foundation production SwiftPM suite under WSL Swift **6.4**:
  **51 passed**, zero failures. Includes 21 store, 8 policy, 5 query, 4 spy,
  10 online-history and 3 preexisting shortening cases.
- Owned production/tests and patched native sources pass tree-sitter Swift checks;
  patched sources introduce no additional parser diagnostics.
- Native `swiftc -frontend -parse` passed for the seven changed Postbox/UI adapters
  under WSL; their platform-dependent imports are not type-checked by parsing.
- Scoped `git diff --check` passed.

Commands from `ios-build-ci`:

```powershell
$env:WHITEGRAM_ASSEMBLED_SOURCE='C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0'
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B -m unittest discover -s whitegram/tests -p 'test_history*.py' -v
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B -m unittest discover -s whitegram/tests -p 'test_online_history.py' -v
& 'C:\coding\telegram\whitegram\whitegram-rebuild\.venv\Scripts\python.exe' -B -m unittest discover -s whitegram/tests -p 'test_history_original.py' -v
wsl -d Ubuntu -- python3 /mnt/c/coding/telegram/whitegram/ios-build-ci/whitegram/tests/history/run_native.py --swift /opt/swift/usr/bin/swift --temp-root /tmp
```

## Real remaining limitations

- Full TelegramCore/UIKit type/link validation and visual/device behavior require
  the parent's macOS build. Foundation tests do not compile Postbox/UI adapters.
- JSON contains no media payloads, thumbnails or usable resource backups.
  Native retained attachments depend on existing Telegram cache lifetime.
  Custom emoji IDs survive entity conversion, but sticker-pack reference objects
  are not part of the portable entity subset.
- Secret chats, never-received/deleted-before-receipt messages and cloud backfill
  remain unavailable. Restoring an absent message needs a known peer and complete
  text; local copies preserve identity/formatting without sending anything.
- Spy persistence is queued and bounded, with crash-before-write loss possible.
  Read dates are learned when the existing native report request succeeds; they
  cannot be recovered from hidden/no-date updates. Saved last-seen evidence is
  historical, and coarse-status fallback can be older than current presence.
  Title/profile redraw on their normal presence refresh; toggling the preference
  does not independently force a title/profile redraw in this slice.
- Multi-device revision reconciliation and a transactional archive/Postbox backup
  are not implemented. Original unscoped files require explicit destination-account
  binding. Parent owns logout cleanup and account-scoped preferences.
