# Local pinned chats port

## Delivered

`local_pins_patches.py` and three new Swift files provide a local pin overlay for
ordinary chat lists: the main group, archive group, and custom chat filters.
The implementation supplies persistent local membership, mixed local/cloud order,
native pin/unpin actions, off-page peer loading, and native drag reorder hooks.

This is a cleanroom behavior design. Original accessor evidence is verified below;
the original app's storage format and overflow/reorder semantics have not been
recovered. Build 34652 connects `LOCAL_PINS_BOOLEAN_CAPABILITIES["unlimitedPinnedChats"]`
to the catalogue and integrates local filter-deletion and account-logout cleanup.
Apple release/simulator compilation passed in [build 34652](BUILD_34652.md).
Signed-in device interaction validation remains pending.

## Installer contract

```python
from local_pins_patches import RUNTIME_FILES, local_pins_patches, apply_local_pins_patches

# Preferred: stage inside the parent's SourcePatches transaction.
local_pins_patches(patches)

# Standalone writing entry point, for a caller-selected assembled tree:
inventory = apply_local_pins_patches(root)
```

Copy the following runtime files from `cleanroom/` before building. The exported
`RUNTIME_FILES` and alias `LOCAL_PINS_RUNTIME_FILES` have precisely this mapping:

| File | Destination |
|---|---|
| `WhitegramLocalPinPolicy.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramLocalPinPolicy.swift` |
| `WhitegramLocalPinRuntime.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramLocalPinRuntime.swift` |
| `WhitegramLocalPinList.swift` | `submodules/ChatListUI/Sources/Node/WhitegramLocalPinList.swift` |

Existing target source globs and dependencies cover these files;
`LOCAL_PINS_REQUIRED_DEPENDENCIES = {}`. Requires the parent's existing
`WhitegramPreferences` account-profile API (`scope` and `readProfileForTransfer`)
and the assembled Telegram 13 community-summary helper. Exact anchors were checked
against read-only `whitegram-source-13.0.0`, the same assembled tree described in
`CLIENT_INTERFACE_PORT.md`.

The patcher stages eight existing Swift files. Its inventory has these keys:
`local-pins-toggle`, `local-pins-menu`, `local-pins-reorder`, `local-pins-errors`,
`local-pins-projection`, `local-pins-loading`, `local-pins-pagination`,
`local-pins-rank`, `local-pins-account-removal`, `local-pins-filter-removal`.
It adds a `localPinError` result and patches both existing
result consumers with a visible error alert. It exports `local_pins_edits()` for
parent preflight/inspection.

### Required parent integration routes

1. Install `RUNTIME_FILES`, invoke the staging/writing entry point, and include
   the new tests in the parent build checks.
2. Retain the existing boolean preference row/write route for
   `unlimitedPinnedChats`. The runtime reads the explicit account's selected
   preference profile, not whichever account happens to be active globally.
   Review and update capability bindings only after the remaining checks below.
3. On **confirmed deletion of a custom filter**, call
   `try WhitegramLocalPinStore.shared.removeScope(accountId: account.id.int64,
   scope: .filter(filterId))`. Telegram can reuse numeric filter IDs. Deletion
   cleanup must run before such reuse; absent filters are already excluded by
   runtime membership checks. Report a cleanup failure instead of replacing a
   malformed store.
4. On **confirmed account removal**, call
   `WhitegramLocalPinStore.shared.reset(accountId: removedRecordId.int64)`.
   The same method is the explicit user-requested reset/recovery action. Do not
   call it when merely switching accounts or disabling the toggle.
5. Settings transfer must not transplant `WhitegramLocalPins.v1.<recordId>` to
   another account. This operational state has its own account-owned store; it
   is not one of the canonical preference snapshot's keys.

Build 34652 installs this module through the shared composition. Filter edits
remove all deleted scopes in one write and retain the current filter list if
cleanup fails. Logout resets pins inside the subscribed account transaction.
The writing wrapper is exercised on scratch copies; the reference source is read-only.

## Behavior and persistence

Each AccountRecordId owns one UserDefaults `Data` value named
`WhitegramLocalPins.v1.<decimal recordId>`. Its versioned JSON document contains
scope keys `g:<raw groupId>` and `f:<filterId>`. Three ordered arrays are stored:

- `local`: locally pinned peer membership;
- `hidden`: cloud pins explicitly unpinned in the local view;
- `order`: local order of mixed local and cloud pins, retaining dormant IDs.

All packed PeerIds use canonical decimal **strings**, preserving the complete
signed Int64 value. Decoding rejects numeric IDs, duplicate IDs, noncanonical or
overflowed decimals, overlapping local/hidden membership, invalid scope keys and
unsupported document versions. Failed changes retain the saved bytes. A shared
recursive lock serializes reads and updates across store instances, and changes
notify observers after unlocking. This is ordinary UserDefaults persistence;
crash/power-loss durability is not asserted.

While enabled, new pin actions always add local membership, even if a cloud slot
is available. Unpinning an existing cloud pin hides it locally. Re-pinning it
removes that suppression and puts it first. Neither operation changes cloud
membership. Cloud pins from other clients are merged into the local view; remote
removal removes cloud-only membership, and newly seen cloud pins append after the
saved order. A peer explicitly pinned locally retains local membership if another
client later pins and unpins the same peer. Explicit local suppression persists
until re-pin/reset.

Reorder validates both the expected current sequence and exact membership before
committing. It refuses partial/duplicate/stale lists. A local operation captured
by a menu/drag carries an origin flag through the engine API, so disabling the
feature while it is in flight cannot fall through to the stock server mutation.
Disabling retains saved local data and restores the stock list; re-enabling
restores local order.

Group membership is checked against `Transaction.getPeerChatListIndex`.
Moved/deleted peers disappear from an inapplicable group while their stored rank
is retained for a later return. Custom-filter pins behave as explicit inclusions:
they can display an existing root/archive peer even when that filter's ordinary
category/read/mute/archive predicate excludes it. A missing filter or missing
chat-list peer cannot be pinned. Expanded communities are refused, as in the
native pin path; collapsed community summaries use the native summary helper.

## Loading and native interaction hooks

- The existing engine `toggleItemPinned` and `getPinnedItemIds` entry points serve
  the context menu/search-menu pin action and swipe action. Normal row rendering
  supplies the native pin icon, reveal action state, and drag handle.
- A separate live `AccountViewTracker.tailChatListView` uses an include-only peer
  predicate across root/archive. It fetches stored pins outside the current main
  page, carries native row payloads, and observes their updates. Local IDs never
  enter the stock `pinnedPeerIds` loader, which converts ranks to UInt16.
- Community summaries run on the fetched rows. The detached displayed item keeps
  messages, drafts, counters, mention/reaction/poll flags, presence, story stats,
  contact/mute status, failures, media drafts, and other native fields.
- Display ordering uses a separate `[PeerId: Int]` rank map and a rank-aware
  `ChatListNodeEntry` comparator. A constant transient `pinningIndex: 0` is only a
  native row presentation flag. No rank is narrowed to UInt16 or written back to
  Postbox's persisted chat-list indices.
- Off-page loading and the main page both retain actual Postbox navigation
  anchors. Main windows request `ordinary count + effective pin count + hidden cloud pin count` so removing
  pins from the ordinary rows cannot empty a pin-only page. Older pages exclude
  the projected pins instead of repeating them. The end-of-page trigger uses the
  displayed row count while the next anchor comes from the unmodified base list.
  Locally unpinned cloud peers are fetched independently into the page containing
  their real timestamp, rather than appearing prematurely at the bottom of page one.
- The drag hook passes the expected mixed order to the local reorder transaction.
  Cloud pin reads use direct group/preference reads; they do not invoke the stock
  filter-normalization writer. There is no local-path `setPinnedItemIds`, filter
  mutation, sync operation, or raised server limit.

## Original evidence

`tests/local_pins/check_original.py` directly reads the supplied IPA and verifies
its SHA-256, the arm64 Mach-O mapping, and all three retained pin accessor byte
digests from `recovered-3.2/native/TelegramCoreFramework-0/symbols.json`:

- IPA: `5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.
- TelegramCore framework:
  `9908ba0fcf3782f6f7da9a3b4f82b941cc95c952ba1b631cb33451747e96e198`.
- Getter `0x22c708..0x22c778`:
  `802e30de240ffaa47adb8cdd6ce77454eab749e33c9d8d5afd2925443d21035c`.
- Setter `0x22c778..0x22c7f0`:
  `8b0fb7a588260e076fdeccb89996d6e734d70a6cd7b90b8211b82c73cc361360`.
- Modify accessor `0x22c7f0..0x22c81c`:
  `3d9e275679b2fd78d8430eab8a7de7af2ed7ba4ff94464e53c63f155f848aafa`.

These establish accessor identity/bytes, not the original overflow algorithm.
The recovered `wg_unlimitedPinnedChats` key and the incomplete recovery described
in `CLIENT_INTERFACE_PORT.md` remain the original-feature evidence boundary.
No legacy pin-store migration or original behavior equivalence is claimed.

## Executed checks

Using `C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe`
and WSL `/opt/swift/usr/bin/swiftc` 6.4, Swift 5 mode with warnings as errors:

- **7 Python tests passed** against the real read-only assembled source:
  exact replay/newlines, every missing anchor with composed-state rollback,
  no writes on late failure, mixed/duplicate rejection, injected replacement
  failure with rollback, concurrent preimage modification and runtime-map checks.
- **11 Swift files parsed**, including the eight patched original files.
- **48 compiled policy/storage checks passed**, including 70,000 local pins,
  complete Int64 roundtrip, account/group/filter isolation, reopen, invalid-store
  retention, reorder conflicts, removal/restoration, and explicit scope reset.
- **40 compiled runtime/list checks passed** using the actual three new runtime
  files and actual shared `WhitegramPreferences` with explicit small API fixtures:
  off-page pin fetching, mixed order, native row payload preservation, navigation
  anchors, older-page exclusion, chronological cloud-unpin placement, archive/folder projection, live preference/order
  refresh, explicit-account preference selection, disable retention, observer disposal, membership changes, malformed
  storage, and no fixture cloud-state mutation.
- **3 original accessor byte ranges plus IPA identity passed** with the standard
  Python environment; no Capstone dependency is required.

Reproduction from this directory:

```powershell
$env:WHITEGRAM_LOCAL_PINS_SOURCE = 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0'
$env:WHITEGRAM_LOCAL_PINS_SCRATCH = 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode'
$python = 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe'
& $python -B -m unittest discover -s tests -p test_local_pins.py -v
& $python -B tests/local_pins/run_checks.py --source $env:WHITEGRAM_LOCAL_PINS_SOURCE --scratch-parent $env:WHITEGRAM_LOCAL_PINS_SCRATCH
& $python -B tests/local_pins/check_original.py --ipa 'C:\coding\telegram\whitegram\Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa' --recovery 'C:\coding\telegram\whitegram\whitegram-rebuild\recovered-3.2'
```

## Remaining limits and verification

- Local filter-edit and logout hooks are installed; remote filter deletion and
  subsequent reuse of the same filter ID still require lifecycle validation.
- Apple SDK/Bazel device and simulator builds passed. Signed-in interaction
  validation remains open. In particular, verify
  merge-list animations, drag cancellation/concurrent refresh, swipe/menu alerts,
  archive headers, filter changes, scroll-back across page boundaries, unread/
  story updates and hole filling with real Postbox/SwiftSignalKit scheduling.
- This port covers ordinary chat-list peers. Forum-topic pins, Saved Messages
  subdialogs, message pins, and peer-picker ordering use their existing paths.
- Loading/memory work scales with the local pin count, including extra main-window
  rows. The 70k check validates policy rank width, not acceptable 70k-row device
  performance. Large-account profiling and a more incremental projection are open.
- Peers without an existing Postbox chat-list entry are withheld. The port loads
  known dialogs outside pagination; it does not import unknown remote peers from
  a legacy ID-only store.
- Storage is local to this installation/account record and does not synchronize
  to other clients. Explicit account deletion/reset removes it; toggle-off does not.
- English local-storage alerts are functional but not yet localized.

The standalone writing wrapper preserves byte preimages, modes, and CRLF/LF,
checks concurrent modification, and rolls back ordinary I/O failures. Failed
rollback retains backup files for recovery. It is not crash-atomic multi-file
publication; use the parent's staging transaction when composing modules.
