# Local navigation and backgrounds

This independent port supplies seven runtime files and 29 staged source edits for
the assembled Telegram 13.0 tree. Parent installer/menu integration and an Apple
build are still required before these features are available in a distributed app.

## Implemented scope

| Setting/action ID | Consumer and behavior |
| --- | --- |
| `separateProfileTab` | Adds a real `PeerInfoScreenImpl(isSettings: false, isMyProfile: true)` after Settings. Keeps the selected controller by identity; removing the selected Profile falls back to Chats. Settings and app-icon deep links use the actual Settings instance. Profile titles/icons survive upstream presentation updates. Disabling releases the extra controller. |
| `hideBottomTabBar` | Hides the production tab component, its hit testing, accessibility descendants and disabled overlay; removes its content inset. A 44-point top-edge **Switch tab** button exposes all installed tabs and **Show bottom tab bar**. Restoring persists `false`. Native temporary hiding during search/editing remains independent; native toolbars retain their inset. No `compactPanel` assignment or mapping is used. |
| `profileCoverPhoto` | Files picker imports an image, decodes/downsamples to at most 2048 pixels, encodes JPEG, saves it locally, and displays it in the own-profile/settings header. A theme-colored wash protects text contrast. |
| `resetProfileCoverPhoto` | Clears the current account/settings-scope cover reference; restores the upstream header background when no profile video takes precedence. |
| `videoChatBackground` | Files picker imports a playable, non-protected video with a video track, maximum 40 MiB / 60 seconds. A muted `AVQueuePlayer`/`AVPlayerLooper` renders in the real chat wallpaper view. |
| `resetVideoBackground` | Clears the video reference and `videoBackgroundInProfile` together; live observers tear down player, looper, KVO and image state. |
| `videoBackgroundInProfile` | Applies that video to the own-profile/settings header. Video takes precedence over a still cover. Disabling this flag restores the cover and leaves chat video enabled. |
| `chatListPreview` | Opens the real account chat-list controller with `previewing: true`, no history-preload ownership and no debug actions. This is an interactive account-backed preview. |
| `tabBarPreview` | Uses the production `TabBarControllerImpl`/`TabBarComponent` with clearly labelled sample pages, current theme and tab settings, live preference refresh, selection and an explicit Back button. Its “Show bottom tab bar” action is preview-local and never writes preferences. |

### Deliberate boundaries

- `showPostsFeed` remains unsupported. Recovered metadata names
  `WGPostsFeedController` (`types.json`, descriptor `0x5cdc92c`) and feed state,
  but does not supply a source-compatible timeline, pagination, deduplication,
  media lifecycle or read-state implementation. A bounded search of assembled
  `submodules/**/*.swift` found the setting/state/localization entries but no
  `PostsFeed`/`ChannelFeed` controller declaration. No channel-list substitute is
  registered as a posts feed.
- `classicInterface` remains unsupported. Existing client-interface code changes
  header material only. This package does not claim restoration of the complete
  legacy navigation, chat list, menus, toolbars and transitions.
- Video coverage is **chat wallpaper plus the optional own-profile/settings
  header**. Call-screen backgrounds, other users' profiles, full-interface video,
  media editor screens and video-aware bubble/edge-effect sampling are outside
  this port. Bubble sampling continues to use Telegram's underlying wallpaper.
- Expanded avatar galleries, editing headers, media-only headers and collapsed
  offscreen headers suppress the local profile layer. Resetting returns to the
  upstream renderer; no server peer/avatar/theme is modified by background actions.
- Video pauses when the controller disappears, its view leaves the window, the
  app resigns active, Reduce Motion is enabled or Low Power Mode is enabled.
  Controller teardown releases observations and playback objects. Frame-perfect
  Apple rendering, interruption handling, codec behavior and battery use require
  device validation.
- Picker is **Files**, with single-file selection. Covers are limited to 8 MiB
  input/output; videos to 40 MiB. Import and disk writes run off the UI thread.
  Errors surface in the editor and runtime failures log and reveal the base
  wallpaper/header. There is no crop editor, Photos-specific picker or trimming UI.
- New helper UI labels are English; original multilingual UI/visual parity is not
  claimed. The two previews are navigable screens, not original inline preview rows.

## Evidence and API boundary

- Read-only reference: `C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0`.
  `upstream.json` identifies upstream tag `release-13.0.0`, SHA
  `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`; the assembled overlay has additional edits.
- Recovery: `whitegram-rebuild/recovered-3.2/CATALOG.md`,
  `WGRecoveredPreferenceKeys.swift`, and
  `native/TelegramUIFramework-0/types.json`. The catalog reports original input
  SHA-256 `5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.
  This pass reuses those records; it does not claim a new IPA digest verification,
  native decompilation, original runtime observation or binary parity.
- Original supplied IPA: `Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa`.
  No reference or IPA writes are required by these checks.
- Reviewed actual source declarations/call sites: `PeerInfoScreenImpl` initializer
  and its `isMyProfile` parameter; `parentController`; `makeChatListController`;
  `TabBarControllerImpl.setControllers`, selection, transient hiding and layout;
  `ContainerViewLayout` insets; header banner geometry; chat wallpaper node and
  controller appearance callbacks. The peer initializer without `isMyProfile`
  would produce a media-only self screen, so that argument is intentional.
- UIKit/AVFoundation/ImageIO are Apple SDK dependencies, not external packages.
  Target iOS 15+ with the existing Swift 5 language mode. Swift parsing on Linux
  does **not** type-check UIKit or link the iOS targets.

## Storage and account isolation

All values use the existing `WhitegramPreferences` implementation. No preference
implementation changes are needed. `WhitegramNavigationSettings` is compiled
inside TelegramCore so it can use the existing internal
`readProfileForTransfer(scope:_:)` and `updateProfileForTransfer(scope:_:)` APIs.

Reads use `scope(accountId:)` for the controller's `AccountRecordId.int64`, not the
currently foregrounded account. Scope is rechecked under the preference lock.
Updates use the same explicit scope and canonical commit/notification path.
Pickers capture the scope before presenting, recheck before writing and again
before preference commit, and report a scope change instead of saving into the
new scope. Shared settings deliberately share a media reference; separate account
settings inherit and then isolate snapshots according to the existing API.

| Key | Type/default | Purpose |
| --- | --- | --- |
| `separateProfileTab` | Boolean / false | Extra self-profile controller |
| `hideBottomTabBar` | Boolean / false | Persistent real tab hiding |
| `videoBackgroundInProfile` | Boolean / false | Own-header video opt-in |
| `navigationProfileCoverFile` | String / empty | Managed JPEG filename |
| `navigationVideoBackgroundFile` | String / empty | Managed movie filename |

Media lives in Application Support / `WhitegramLocalBackgrounds`, with generated
lowercase UUID filenames. Readers reject non-managed names, URL/absolute/traversal
references, symlinks, nonregular files and oversized/missing files. Reset removes
the active preference reference, **not** files that other account/shared snapshots
may still reference. Unreferenced files, including a file whose later preference
commit failed, are retained; there is no garbage collector in this scope.

Legacy absolute `wg_profileCoverPhotoPath` / `videoBackgroundPath` values are not
trusted or migrated; select the asset once in the new editor. Current portable
settings archives do not include these two new filename keys or media bytes.
This port does not advertise portable background transfer.

## Complete parent integration map

The following are instructions for the parent owner; these parent files have not
been changed by this package.

### 1. Installer and staged patch registration

In `compat-12.9.4.py`, import:

```python
from navigation_patches import RUNTIME_FILES as NAVIGATION_RUNTIME_FILES, apply_navigation_patches
```

Add `NAVIGATION_RUNTIME_FILES` to the runtime-manifest loop and
`apply_navigation_patches` to the patcher loop **after the existing root/tab,
appearance, player, profile, client-interface and Telegram-13 adaptations**.
It was checked against the fully assembled reference, not a raw checkout.
Keep it before the final patched-source dependency scan. Merge returned paths
into `patched_sources` exactly like the other patchers.

For a parent transaction instead:

```python
from source_patches import SourcePatches
from navigation_patches import navigation_patches

patches = SourcePatches(source_root)
# Parent stages its prerequisite edits first.
navigation_patches(patches)
report = patches.write()
```

`navigation_patches` writes nothing and restores the caller's staging dictionaries
if any anchor fails. It rejects missing, duplicate, mixed-original/installed and
duplicate-installed anchors. Reapplying succeeds without changing bytes.
`apply_navigation_patches(root)` explicitly calls `patches.write()`. Its filesystem
write/line-ending semantics are those of `SourcePatches.write`; it does not add
transactional I/O rollback or byte-preserving CRLF output to that parent API.

### 2. Runtime files and dependencies

Copy each `cleanroom/<name>` to its `RUNTIME_FILES[name]` destination:

| Runtime file | Destination directory |
| --- | --- |
| `WhitegramNavigationPolicy.swift` | `submodules/TelegramCore/Sources/Settings/` |
| `WhitegramBackgroundStore.swift` | `submodules/TelegramCore/Sources/Settings/` |
| `WhitegramBackgroundView.swift` | `submodules/TelegramPresentationData/Sources/` |
| `WhitegramBackgroundController.swift` | `submodules/SettingsUI/Sources/` |
| `WhitegramNavigationPreviewController.swift` | `submodules/SettingsUI/Sources/` |
| `WhitegramNavigationTabAccess.swift` | `submodules/TabBarUI/Sources/` |
| `WhitegramNavigationRoot.swift` | `submodules/TelegramUI/Sources/` |

Ensure SettingsUI has Bazel dependency **`//submodules/TabBarUI:TabBarUI`**.
`REQUIRED_DEPENDENCIES` exports this requirement. The normal installer import scan
can add it once the new runtime files are registered. All other non-SDK imports
already have dependencies in the inspected targets; their recursive Swift globs
include the new files. The dependency direction is SettingsUI → TabBarUI, with no
reverse dependency. Ensure any alternate SwiftPM/generated-Xcode manifests also
include the new sources/dependency if that build lane is used.

### 3. Capabilities and generated settings routes

In `WhitegramPortCapabilities.booleans`, map these IDs to the same-named keys:
`separateProfileTab`, `hideBottomTabBar`, `videoBackgroundInProfile`.
Keep `showPostsFeed` and full `classicInterface` unavailable.

Replace the old Russian `hideBottomTabBar` override that describes a compact menu
with **`Скрыть нижний таббар`** (or use the recovered localization key).
Do not bind it to the fork's compact-panel setting. In the parent coordinator's
boolean update path, use `try WhitegramNavigationSettings.update(changes,
accountId: self.context.account.id.int64)` for these three keys and show save
failure on error; this preserves the controller-account binding during switching.

Add these `WhitegramPortCapabilities.screens` mappings:

| Row ID | Screen identifier |
| --- | --- |
| `profileCoverPhoto` | `navigationCover` |
| `resetProfileCoverPhoto` | `navigationResetCover` |
| `videoChatBackground` | `navigationVideo` |
| `resetVideoBackground` | `navigationResetVideo` |
| `chatListPreview` | `navigationChatPreview` |
| `tabBarPreview` | `navigationTabPreview` |

Add these cases to `WhitegramSettingsCoordinator.open(_:)` in
`WhitegramGeneratedSettingsScreen.swift`:

```swift
case "navigationCover":
    target = WhitegramBackgroundController(context: self.context, kind: .cover)
case "navigationVideo":
    target = WhitegramBackgroundController(context: self.context, kind: .video)
case "navigationChatPreview":
    target = whitegramChatListPreviewController(context: self.context)
case "navigationTabPreview":
    target = WhitegramNavigationPreviewController(context: self.context)
case "navigationResetCover":
    do { try WhitegramBackgroundStore.reset(.cover, accountId: self.context.account.id.int64) }
    catch { self.saveFailed() }
    return
case "navigationResetVideo":
    do { try WhitegramBackgroundStore.reset(.video, accountId: self.context.account.id.int64) }
    catch { self.saveFailed() }
    return
```

The existing screen-route row branch renders both preview IDs as disclosure rows;
no inline custom item type is necessary. Reset rows can use the parent's action-row
styling, but must dispatch the reset case rather than merely open an editor.

### 4. Source consumers covered by the patcher

- `TelegramUI/Sources/TelegramRootController.swift`: observer and state lifetime,
  initial composition, live composition, settings/app-icon identity-based routing.
- `TabBarUI/Sources/TabBarController.swift`: independent persistent/native hidden
  state, prelayout insets, accessible switcher and restored selection.
- `TabBarUI/Sources/TabBarContollerNode.swift` (upstream spelling): actual tab view
  visibility/accessibility/hit testing, disabled-overlay hiding, safe/toolbar
  bottom inset, absent anchor geometry for hidden tabs.
- `PeerInfoScreen/Sources/PeerInfoScreen.swift`: self-profile tab identity and
  background appearance/disappearance lifecycle.
- `PeerInfoScreen/Sources/PeerInfoHeaderNode.swift`: own-header cover/video layer,
  geometry and gallery/editing/collapse suppression.
- `TelegramUI/Sources/ChatControllerNode.swift`: video wallpaper placement/layout.
- `TelegramUI/Sources/ChatController.swift`: offscreen playback suspension/resume.

### 5. GitHub build handoff

After the parent integrates the manifests, dependency, capabilities and routes,
run the normal assembled-source validation and the existing macOS/iOS GitHub build
lane. This package does not dispatch a build of an unchanged remote commit. No
commit/push or workflow modification was performed. Apple type checking, linking,
IPA packaging and device QA remain build/release acceptance gates.

## Reproducible checks

Run from `C:\coding\telegram\whitegram\ios-build-ci\whitegram`:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:WHITEGRAM_NAVIGATION_SOURCE = 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0'
$env:WHITEGRAM_NAVIGATION_SCRATCH = 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode'
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B -m unittest discover -s tests -p test_navigation.py -v
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B tests/navigation/run_checks.py --source $env:WHITEGRAM_NAVIGATION_SOURCE --scratch-parent $env:WHITEGRAM_NAVIGATION_SCRATCH
```

`run_checks.py` copies only seven target files to a fresh scratch directory, stages
and reverses edits, exercises the writing wrapper and replay, parses all 14 patched
and runtime Swift files, then compiles/runs the real Preferences + navigation/media
policies using WSL `/opt/swift/usr/bin/swiftc`. It runs a separate process to check
persistence and emits exact input SHA-256s. Preferences/media test writes are
confined to a scratch HOME/XDG root. Remove `WHITEGRAM_NAVIGATION_SOURCE` to run the
unit suite against synthetic anchors as well.

Checked locally: 7 Python tests passed against both assembled and synthetic
anchors; 14 Swift files parsed; 73 Foundation policy/account/storage checks and
5 separate-process persistence checks passed (Swift 6.4, Swift 5 language mode).
The checked production APIs were read from the assembled source. No iOS SDK
type-check, simulator screenshot, original visual comparison or GitHub artifact
is claimed by these results.

### Device acceptance cases

1. Enable Profile on Chats and on Settings; keep selection and verify each tab's
   content and deep links. Disable while on Profile; land on Chats. Switch accounts
   with separate settings both on and off; no wrong-account profile or background.
2. Hide tabs in portrait/landscape and split view. Verify the bottom region has no
   invisible touch target or VoiceOver tab items; switch all tabs and restore via
   the top button. Open/cancel search and edit selection; confirm native cancel and
   toolbar actions remain usable and content insets restore.
3. Import/replace/reset covers and movies. Test invalid/oversized/protected files,
   picker cancel, changing settings scope while picking, relaunch, offscreen
   transitions, background/foreground, Low Power and Reduce Motion. Observe actual
   player/looper release after reset and screen destruction.
4. Own profile/settings gets media; another user's profile and expanded avatar
   gallery do not. Disable profile video with a saved cover and verify restoration.
5. Open both previews, change theme/tab settings, rotate, use Back and VoiceOver;
   preview-only restoration must not mutate stored `hideBottomTabBar`.
