# Remaining presentation / information handoff — Whitegram 3.2 / Telegram 13.0

## Delivered

`remaining_presentation_patches.py` stages seven real upstream source consumers against the read-only assembled 13.0 tree. `RUNTIME_FILES` maps seven new `WhitegramRemaining*.swift` sources; `RESOURCE_FILES` maps the two recovered badge images and their asset manifests. The parent still needs to install these maps and make the registry/router edits below.

| Requested item | Implemented boundary | Remaining limit |
|---|---|---|
| `appBadgeColorIsBlack` | The original menu case now opens a **badge-name selector**, writes `appBadgeName`, and updates the existing `Window1.badgeView` from `TelegramRootController`. | Black/White images available here; Primary and other catalog variants remain unrecovered. No SpringBoard badge alteration. |
| `hideWhitegramUserBadge` | Existing authorized profile service supplies grants to post-author, chat-list and chat-header name rendering. Live preference updates remove the decoration. Profile presentation remains unaffected. | Measured inline `✦` glyph rather than the original icon/particle layer. Search-as-message author titles are not decorated. Native visual comparison remains open. |
| `hideOthersCustomMessageStyle` | Recovered and executable-tested the incoming-only gate, including early exclusion/media eligibility. | **Not a connected capability.** No `WGMessageStyleManager`, per-user/chat style cache, or style delivery exists in the inspected assembled tree. Ordinary incoming themes, entities and Telegram peer colors are not substitutes. |
| `scammerProtection` | Normal peer profiles now consume existing `whitegramScammerAssessment`, show the recovered warning text for a listed CloudUser, and refresh when preferences/cache change. The card labels the saved-list source and timestamp. | **Legacy-cache UI only.** The existing adapter has no signed-snapshot verifier; missing/corrupt/not-listed produces no positive warning or “safe” verdict. |
| Five information/preview IDs | Exact existing localization keys for the four help rows; icon-pack site disclosure opens a localized description, existing builder URL and pack help. | Site preview is a native information/link screen, not an HTML screenshot clone. |

## Original semantics and evidence

Original IPA: `C:/coding/telegram/whitegram/Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa`.
SHA-256: `5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.

REA `open_binary` independently reported this identity. Focused disassembly uses the existing `whitegram-rebuild/.venv` and `wgtool.binary.MachO`, reading archive members in memory. `tests/remaining_presentation/evidence.json` records complete function hashes, exact call sites, bounded negative results and unresolved items; `check_original.py` verifies the ledger against the original bytes. This is static evidence, not an original-device observation.

### App badge: the menu case name is obsolete

* UI `0x10f1474` and `0x11057f0` read the old color Bool into settings state; the latter stores it at `+0x12b`. The 72-image imported/exported-symbol B/BL scan found no other direct renderer caller of that Bool. Inlining/computed calls remain outside that scan.
* UI `0x1100304` reads `appBadgeName` at `0x1100334` and constructs `WGBadgePickerController(selectedName:)`. Its callback `0x110073c` writes **`appBadgeName`** at `0x110077c`.
* UI `0xf6a59c` derives badge names from `WhitegramAppIcons.all` by replacing the `WG` prefix with `WGBadge`, then constructs `Components/` resource names. `WGBadgeOption.resolved` (`0xf6a924`) falls back to the primary option. Core `0x22a914` defaults the stored name to `WGBadgePrimary`.
* UI `0x8c36c` / `0x572a1c` read this name, resolve a badge image and call `setImage:`. The matching public source surface is `Display/Source/WindowContent.swift`: `Window1.badgeView`, centered at `y = 5`, with `deviceMetrics.showAppBadge`, portrait and foreground gates.
* Exact loose original `WGBadgeBlack.png` / `WGBadgeWhite.png` are 176×44. The handoff registers them at 2× (88×22 logical points, matching the existing 22-point badge envelope). The scale choice is a port layout decision; the PNG bytes are unchanged. Missing saved variants are explicitly reported in the picker; the window uses its existing baseline `Components/AppBadge` rather than presenting a fabricated recovered variant.

### User badge: grant semantics, not just `enabled`

UI `0x1eb6c88` tests hide at `0x1eb6cb8`, then uses `WGProfileBadgeManager.cached` / `fetchIfStale`. Hidden state removes an existing layer. The fetched state is tested with `hasGrantedBadge` at `0x1eb6e28`. Its max-age constant at `0x54e7e08` is 600 seconds; the handoff's 30-second refresh interval is an explicit client implementation choice.

Core `0x2b68e4` establishes the grant policy:

1. Explicit `granted` Bool wins, including `false`.
2. Otherwise a nonempty role other than exact `beta_tester`, or nonempty `badgeText` / `verificationText`, qualifies.
3. `enabled` is not read by this grant getter. A beta session by itself is not a grant.

Additional direct hide consumers: UI `0x184f520`, `0x185da98`, `0x1a4dee4`, `0x1a4e598`, `0x1eac21c`. Recovered `s.hideWhitegramUserBadge.desc` explicitly scopes hiding to posts/list/header while retaining the profile badge.

The adapter uses the existing `WhitegramProfileService.fetch(... resource: .badge)` with explicit account/target IDs. Account/user subscriptions coalesce. Last-subscriber teardown cancels work; session/access/profile mutations discard old results before rebinding; generation checks reject late callbacks and reused-cell identities. Successful responses refresh at a bounded 30-second interval while subscribed; authorization is checked each second so silent expiry removes displayed grants. Existing backend transport throttling, authorization and response validation still apply. No endpoint, identity authority, server mutation or local grant override was added.

### Other-user message styles

UI `0x1839048` first checks an early-exclusion Bool (its source-level name is unresolved, so the policy calls it `excluded`). Incoming calls read `hideOthersCustomMessageStyle` at `0x1839080` and exit on true, **before** `supportsCustomStyle`, `style(userId:chatId:)`, timestamp resolution and prefetch. Outgoing calls instead use `ownStyle(chatId:messageTimestamp:)`. The pure policy captures this decision, but this handoff does not invent the missing style manager. Keep the control out of the parent's supported booleans until that renderer/data source exists.

### Scammer snapshot qualification

The assembled `SettingsUI/Sources/WhitegramScammerDatabase.swift` reads `wg_scammerRemoteIdsV1` and `wg_scammerRemoteIdsV1Timestamp`; it parses a comma-separated legacy cache. It contains no signature verification or active fetch. In the **3.2** original, Core `WGScammerDatabaseManager.refreshIfNeeded` at `0x214ee4` is `RET`, and `SGScammerBlacklist.isScammer` at `0x214e9c` is `MOV W0, #0; RET`.

Therefore neither a signed current snapshot nor a live original warning can be established from this tree. The implemented normal-profile card is a consumer of the existing saved-list service, clearly labeled as such. If the parent has a separate signed provider, it must supply its actual API and provenance before this can be called signed-snapshot parity. Recovered label/body keys are `profile.scammerWarningLabel` and `profile.scammerWarningText`.

## Installation / staging API

```python
from remaining_presentation_patches import (
    RUNTIME_FILES, RESOURCE_FILES, remaining_presentation_patches,
    apply_remaining_presentation_patches,
)

# Parent installer: merge RUNTIME_FILES into its cleanroom runtime map.
# RESOURCE_FILES keys are relative to whitegram/, values relative to upstream.
# Copy the complete imagesets through the parent's normal resource installation.

# After backend and the assembled baseline UI patches:
remaining_presentation_patches(staged_source_patches)
# Or, for a writable build tree only:
report = apply_remaining_presentation_patches(root)
```

All edits use exact anchors, reject missing/duplicate/mixed states, and replay without writes. The staging function mutates only `SourcePatches.pending`; no installer, shared preferences, capability/router file or existing patcher was edited. As with the other staged modules, discard the staging object if an exception is raised.

Targets:

* `TelegramUI/Sources/AppDelegate.swift`: installs the existing-service badge bridge after backend installation.
* `TelegramUI/Sources/TelegramRootController.swift`: retains the window badge image binding.
* `ChatListUI/Sources/Node/ChatListItem.swift`: account/peer-bound title decoration and asynchronous relayout.
* `TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift`: independently measured title segment, preserving other status icons.
* `TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift`: effective CloudUser author decoration and message relayout; preview excluded.
* `PeerInfoScreen/Sources/PeerInfoProfileItems.swift` / `PeerInfoScreen.swift`: separate warning section and cache/preference observer.

The maps place policy/identity helpers in TelegramCore, backend/picker helpers in SettingsUI, and the profile item in PeerInfoScreen. They introduce no dependency from TelegramCore or chat/list modules to SettingsUI. Existing module source globs cover the new Swift files; confirm the parent's BUILD lists if it uses explicit source lists.

## Parent-owned registry / route edits

In `WhitegramPortCapabilities.swift` merge these entries (existing keys must not be duplicated):

```swift
// booleans:
"hideWhitegramUserBadge": "hideWhitegramUserBadge",
"scammerProtection": "scammerProtection", // same canonical key as existing profile service UI

// informationKeys:
"hideChannelAdsInfo": "s.hideChannelAds.desc",
"hideWhitegramUserBadgeInfo": "s.hideWhitegramUserBadge.desc",
"hideOthersCustomMessageStyleInfo": "s.hideOthersCustomMsgStyle.desc",
"iconsInfo": "icons.info",

// titleKeys:
"appBadgeColorIsBlack": "s.appBadgeColor",
"hideWhitegramUserBadge": "s.hideWhitegramUserBadge",
"hideOthersCustomMessageStyle": "s.hideOthersCustomMsgStyle",
"iconPackSitePreview": "s.createIconPack",

// screens:
"appBadgeColorIsBlack": "remainingPresentation",
"iconPackSitePreview": "remainingPresentation",
```

`WhitegramRemainingInformation` exports the same help/title maps for a parent that prefers dictionary merging. `iconPackSiteDescriptionKey` is exactly `wh.createIconPack`; its existing destination is `https://whitegram.click`.

In the existing generated-settings router's `switch screen`:

```swift
case "remainingPresentation":
    target = whitegramRemainingPresentationController(context: self.context, id: id)
```

For `hideSettingsDescriptions`, extend the existing filter's information-ID set with `iconPackSitePreview`:

```swift
informationIds: Set(WhitegramPortCapabilities.informationKeys.keys).union(["iconPackSitePreview"]),
```

Keep `iconPackSitePreview` in `screens`, not `informationKeys`: the generic information branch renders plain text before the disclosure branch. The routed preview screen contains the exact localized description, builder action and `icons.info` text. The four other help rows remain plain text and already honor description hiding.

Do **not** register `appBadgeColorIsBlack` as a Boolean control: the current original selector stores the name. Do not register `hideOthersCustomMessageStyle` as completed; only its evidence-backed policy and information are supplied. The normal-profile scammer consumer warrants only a **legacy-cache** coverage description, not signed/current database coverage.

## Verification

Executed with `C:/coding/telegram/whitegram/whitegram-check-env/Scripts/python.exe` and WSL `/opt/swift/usr/bin/swiftc` 6.4, Swift 5 language mode:

* 8 Python tests: actual assembled-source staging, replay, every anchor's missing/duplicate/mixed failure, exact reversal, ownership boundary, native identities, resource digests and localization map.
* 51 compiled/executed policy/binding checks: grant precedence, surface exemption, incoming-only style decision, name defaults, account/peer isolation, reuse, invalidation and teardown.
* 16 compiled/executed **production badge-adapter** checks with a synthetic backend: coalescing, authorization identity, expiry, mutation, late callbacks and last-subscriber cancellation. These do not assert live server acceptance.
* Swift frontend parse of all 7 runtime sources plus all 7 fully staged upstream files. Tree-sitter additionally checks no new errors against the assembled baseline; its older grammar rejects existing `nonisolated(unsafe)` syntax.
* Original verification: IPA/image SHA-256 identities, 9 complete function hashes, 13 direct calls, disabled scammer instructions and exact 176×44 badge resource bytes.

Commands from `ios-build-ci/whitegram`:

```powershell
$env:WHITEGRAM_REMAINING_SOURCE = 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0'
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B -m unittest discover -s tests -p test_remaining_presentation.py -v
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B tests/remaining_presentation/run_swift_checks.py --source $env:WHITEGRAM_REMAINING_SOURCE --scratch-parent 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode'
& 'C:\coding\telegram\whitegram\whitegram-rebuild\.venv\Scripts\python.exe' -B tests/remaining_presentation/check_original.py --ipa 'C:\coding\telegram\whitegram\Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa' --wgtool-root 'C:\coding\telegram\whitegram\whitegram-rebuild'
```

The Swift runner retains scratch files and checks reference bytes again at the end. UIKit/full iOS module type-checking, build/resource compilation, device layout and authenticated server acceptance remain unrun. No commits, pushes, reference writes or deletions were performed.
