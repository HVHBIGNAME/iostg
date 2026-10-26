# Local visual-effects consumers (Telegram 13.0.0)

This scope adds **real render consumers for 13 local settings**. It is ready for the parent installer to integrate. The supplied source tree was read only; the parent owns the iOS/GitHub build. These consumers have bounded evidence support and are not a claim of pixel-identical original behavior.

## Implemented behavior

| Setting IDs to route | Actual consumer | Behavior and boundary |
| --- | --- | --- |
| `avatarBlurEffect` | `PeerInfoScreen.swift` / `WhitegramVisualProfile` | Blurred copy of the current profile avatar behind the screen while the avatar is expanded. Collapsing removes this zoom-only background. |
| `avatarBlurInProfile` | Same | The avatar copy remains behind the profile in the collapsed state. A missing photo or changed account/peer/photo identity clears it immediately. |
| `avatarBlurReduced` | Same | Removes the blur material from the avatar background; the photo copy remains sharp. |
| `avatarBlurTint` | Same | Adds a 35% black tint to the avatar copy. Does not tint controls or the actual avatar. |
| `avatarGlow` | Same | A separate, static shadow-path halo below the profile avatar, colored using the current image's average color. Removed for an expanded avatar, missing photo, editing/search, opt-out and destruction. This is a clean-room interpretation; the complete original key-to-glow call path remains unresolved. |
| `profileColorEffect` | Same | Extends locally available NFT gift status colors, or the peer's effective Premium profile colors, into the profile's screen background. Works without a photo. No Whitegram server color is synthesized. |
| `albumArtBlur` | `OverlayAudioPlayerControlsNode.swift` / `WhitegramVisualAlbumArt` | Actual track artwork drives a blurred background above the native player panel fill and below controls. A 72% native theme-color veil preserves text contrast. Track change, missing artwork and opt-out clear the overlay. |
| `chatScrollAnimation` | `ChatMessageBubbleItemNode.swift` / `WhitegramVisualScrollEffect` | Observes real absolute bubble rect updates and applies bounded additive translation/scale springs. Keeps native rotation, transforms and unrelated animation keys. Resets on reuse, identity change, resize/jumps, visibility loss, context extraction, opt-out and Reduce Motion. |
| `wgBubbleFisheyeEffect` | Profile's `HorizontalTabsComponent` rows | Applies the recovered center-distance scale formula to both regular and selected tab visuals. Hit areas and model frames remain native. Only profile media tabs opt in. Disabled during editing/reordering, window detachment and Reduce Motion. |
| `particleEffect`, `particleMode`, `particleSpeed`, `particleDensity` | Root navigation view (mode 0), chat wallpaper view (mode 1) / `WhitegramVisualParticles` | Snow and autumn leaves rendered by owned `CAEmitterLayer`/`CAEmitterCell` instances. Live mode changes remove the previous emitter. Density and speed use recovered multiplier tables. Resizes update emission geometry; hidden chats, detached views, inactive app, Low Power Mode, Reduce Motion and Off remove emitter cells and layers. |

Every decoration is non-interactive and excluded from accessibility elements. Background effects use image copies, never screen capture or the actual avatar/cover node as a blur target. Native profile header covers, gift artwork, pane panels, navigation material and player controls retain their original drawing and layout.

### Live updates and ownership

`WhitegramVisualEnvironment` keeps one shared subscription to `WhitegramPreferences.updatedNotification`, legacy `UserDefaults` changes, accessibility changes, app active state and Low Power Mode. Consumers hold removable observations with weak callbacks. The adapters retain only their current image/state for live re-enable; disabling removes their visual subtrees. Destruction removes owned layers and observations.

The profile callback chains the AvatarNode's existing image callback, preserving badge updates. It uses the existing image pipeline. The player uses its existing `TransformImageNode.imageUpdated` delivery, rejects nil album-art metadata, and forces the artwork initialization branch after a track identity change. No independent media downloads are introduced.

## Original evidence

Original IPA: `C:\coding\telegram\whitegram\Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa`.

Focused member:

```
Payload/Telegram.app/Frameworks/TelegramUIFramework.framework/TelegramUIFramework
SHA-256: 7f64950144cc75631ceb9cc9365cd4d802d583e5315ee63498829a1c72cb3ac3
```

`tests/visual_effects/original_evidence.json` records the bounded offline observations and original bytes. `probe_original.py` opens the selected IPA read-only and uses the existing `wgtool.binary.MachO`/Capstone environment. Native addresses below belong to that exact member. No original app execution was performed.

| Evidence | Observed facts |
| --- | --- |
| Original C strings `0x5969410`, `0x59697b0`, `0x5969920`, `0x5969a70`, `0x5969e00` | Help explicitly describes horizontal-row fisheye, personal-color profile background, blur around an expanded avatar, profile avatar-copy background and player artwork-copy background. These were checked directly in the original member, alongside recovered `generated/WhitegramLocalizationStrings.swift`. |
| `0x92828c–0x9291e8` | Calls profile-color/avatar-in-profile/reduced-blur/tint getters; obtains `AvatarNode.unroundedImage`; creates an image view, a UIKit blur effect, a black-color tint, and inserts overlays. A separate original Metal mesh branch also exists. |
| `0x83f1dc–0x83f440` | Fisheye getter guard, scroll viewport center, item midpoints, `CGAffineTransformMakeScale`, and identity restoration. Formula: `max(0.45, 1 - abs(itemMidX - center) / 76 * 0.2)`. The public-row selection is a port choice, not a recovered original class identity. |
| `WGChatScrollAnimation.apply(to:offset:)`, `0x18befc4–0x18bf474` | Getter and Reduce Motion guards; transform translation/scale and spring animation. Constants read at `0x554b6e0/6e8/6f0/6f8` establish `-0.66`, `-0.16`, `0.0011`, `0.022`, with translation clamps of 20 and 4. |
| `wgBuildParticleEmitter(size:)`, `0x5c159c–0x5c1c38` | Positive-effect guard, low-power/battery gates, speed/density getters, snow versus leaves resource branches, birth rates 10 versus 7, emitter geometry/velocity/spin and Reduce Motion handling. Tables at `0x6b5acc0` and `0x6b5ad00`: speed `[0.45, 1, 2.2]`, density `[0.45, 1, 2]`. |
| `0x52214–0x52390`, `0x2474ac–0x247690` | Remove previous emitter, then create one only for mode 0 or mode 1 respectively. Together with recovered help (`particle.mode.screen`, `particle.mode.chats`) this supports two placement modes. |
| `0x4d2634`, `0x4d2e30`, `0x4d44f8`, `0x5d6df4` | Direct callers of `albumArtBlurEnabled`; exact native material/opacity remains unestablished. |
| `0x898404` within `0x896ef0` | Fetches `WGGlow.gradientImage`, then configures a layer's contents/gravity/masks/opacity. This corroborates original glow rendering infrastructure but does **not** prove complete `avatarGlowEnabled` semantics. |

Reproduction examples (from repository root):

```powershell
& 'C:\coding\telegram\whitegram\whitegram-rebuild\.venv\Scripts\python.exe' -B whitegram/tests/visual_effects/probe_original.py 'C:\coding\telegram\whitegram\Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa' --wgtool-root 'C:\coding\telegram\whitegram\whitegram-rebuild' --function 0x18befc4
& 'C:\coding\telegram\whitegram\whitegram-rebuild\.venv\Scripts\python.exe' -B whitegram/tests/visual_effects/probe_original.py 'C:\coding\telegram\whitegram\Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa' --wgtool-root 'C:\coding\telegram\whitegram\whitegram-rebuild' --strings 'Blurs the background around|Uses a blurred copy|Buttons in horizontal rows|Fills the profile background'
& 'C:\coding\telegram\whitegram\whitegram-rebuild\.venv\Scripts\python.exe' -B whitegram/tests/visual_effects/probe_original.py 'C:\coding\telegram\whitegram\Whitegram Beta 3.2 (13.0) [tg@heypaintech].ipa' --wgtool-root 'C:\coding\telegram\whitegram\whitegram-rebuild' --verify-record whitegram/tests/visual_effects/original_evidence.json
```

The probe's optional selector annotations are heuristic; exported branch targets, bytes and bounded function ranges are stronger evidence. Unnamed callers are not assigned guessed source class names.

## Parent integration

Import `RUNTIME_FILES`, `visual_effects_patches` and/or `apply_visual_effects_patches` from `visual_effects_patches.py`.

`RUNTIME_FILES` contains exactly:

| Clean-room filename | Destination |
| --- | --- |
| `WhitegramVisualPolicy.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramVisualPolicy.swift` |
| `WhitegramVisualEnvironment.swift` | `submodules/TelegramPresentationData/Sources/WhitegramVisualEnvironment.swift` |
| `WhitegramVisualBackdrop.swift` | `submodules/TelegramPresentationData/Sources/WhitegramVisualBackdrop.swift` |
| `WhitegramVisualProfile.swift` | `submodules/TelegramPresentationData/Sources/WhitegramVisualProfile.swift` |
| `WhitegramVisualScroll.swift` | `submodules/TelegramPresentationData/Sources/WhitegramVisualScroll.swift` |
| `WhitegramVisualFisheye.swift` | `submodules/TelegramPresentationData/Sources/WhitegramVisualFisheye.swift` |
| `WhitegramVisualParticles.swift` | `submodules/TelegramPresentationData/Sources/WhitegramVisualParticles.swift` |

Copy those files through the parent's existing runtime installer. Destination modules already glob `Sources/**/*.swift`, and all seven consuming source paths already import/depend on TelegramPresentationData. No BUILD-file dependency additions are needed for the checked pin.

Staging in the parent's transaction:

```python
from visual_effects_patches import RUNTIME_FILES, visual_effects_patches

# Use the parent's existing SourcePatches instance after its other staged edits.
visual_effects_patches(patches)
# Parent performs its existing full validation and patches.write().
```

Standalone on a writable candidate: `apply_visual_effects_patches(candidate_root)` validates every exact anchor and rechecks source contents before invoking `SourcePatches.write()`. It returns feature-to-path inventory. Neither entry point installs runtime files automatically.

Reversal: `visual_effects_patches(patches, reverse=True)`, then the parent's normal write. Runtime files are owned by the parent's runtime installer. Staging uses a checkpoint and restores any preexisting parent pending changes if this scope fails. Per-edit begin/end markers validate complete installed blocks; missing/duplicate anchors, modified blocks, stripped markers and unmarked conflicting consumers fail closed. File-system writes themselves retain SourcePatches' normal sequential semantics.

Route the exact state IDs in the first table using the existing preferences writer. `particleMode`, `particleSpeed`, `particleDensity` are their actual IDs (not `particleEffectMode`/`particleEffectSpeed`/`particleEffectDensity`). Values:

- Effect: `0 = off`, `1 = snow`, `2 = autumn`.
- Mode: `0 = app-root overlay`, `1 = behind chat messages`.
- Speed and density: `0 = low`, `1 = medium`, `2 = high`.
- All Boolean effects default off. Speed/density default to 1. Invalid/Boolean/fractional enum values are rejected to safe defaults; unknown particle effects turn off.

Historical Boolean fallback names use recovered `wg_avatarBlurEffectEnabled`, `wg_avatarBlurInProfile`, `wg_avatarBlurReduced`, `wg_avatarBlurTintEnabled`, `wg_avatarGlowEnabled`, `wg_profileColorEffectEnabled`, `wg_albumArtBlurEnabled`, `wg_chatScrollAnimation`, `wg_bubbleFisheyeEffect`. Canonical state values take precedence, including explicit false. No preference, settings menu, parent installer or capability file was changed here; the parent should describe the partial surfaces faithfully when routing them.

## Verification

Run from `ios-build-ci`:

```powershell
$env:WHITEGRAM_ASSEMBLED_SOURCE = 'C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-source-13.0.0'
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B -m unittest discover -s whitegram/tests -p test_visual_effects.py -v
& 'C:\coding\telegram\whitegram\whitegram-check-env\Scripts\python.exe' -B whitegram/tests/visual_effects/run_swift_checks.py --source $env:WHITEGRAM_ASSEMBLED_SOURCE
```

Checks include exact install/replay/reversal against pristine pin `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838` and the assembled tree, every anchor's negative cases, changed/stripped blocks, staging rollback, concurrent source drift, callback integration, dependency/source globs and Swift syntax. WSL `/opt/swift/usr/bin/swiftc` parses all 14 production/patched Swift files, compiles policies with warnings as errors, and executes policy plus motion/surface lifecycle programs.

Completed locally: **11 Python tests passed**, all 14 Swift files parsed, all three executable Swift check programs passed. The original-record verifier passed the framework hash, six exact help strings, 12 typed constants and six function bounds. Final Swift check outputs are under `tests/visual_effects/artifacts-a3a419a116/`.

The lifecycle programs execute the production adapters and production notification bridge with a **small UIKit/animation test double and an in-memory preference fixture**. They verify live updates, opt-out, image/identity reset, reuse, retained native animation keys, profile/photo/track cleanup, mode migration, resize, accessibility/power/inactive gates, window detachment and deinit. They do not establish Apple SDK type compatibility, actual blur pixels, real compositor shadow appearance, animation quality, hit-testing on a device, frame pacing or battery use.

The runner writes only fresh `tests/visual_effects/artifacts-*` directories (ignored locally); it verifies the seven input source files' SHA-256 digests stay unchanged. Generated check artifacts are not runtime files. No artifacts or old builds are deleted by this scope.

## Precise remaining gaps

1. **iOS integration/build/device QA:** the parent must install the runtime map and run its iOS build. WSL syntax and fixtures are not an iOS build. Check light/dark profiles, rotation/iPad, quickly changing photos/tracks, Reduce Motion/Transparency, context menus and chat navigation on Apple UIKit.
2. **Profile surface extent:** the effect decorates the screen background exposed around native panels. Native header-cover/gift/pane materials stay over it. Expanded gallery selection/video frames are not sampled; the background follows the current profile-avatar image. Explicit custom profile wallpaper precedence and Metal avatar meshes are not implemented here.
3. **Glow parity:** a real profile-avatar halo is implemented, with image-average color; original dominant-color quantization, bloom texture, extent, per-surface reach and the complete enabled-key call chain remain unknown. This consumer is an approximation, not original parity.
4. **Colors:** local gift/Premium colors are consumed. Original Whitegram-server profile colors and their exact precedence are outside this client-only scope.
5. **Player extent:** the blurred background covers the expanded audio **controls panel**, not the entire playlist or separate full-screen artwork viewer. Actual embedded artwork with absent album-art metadata is not promoted into a background. Exact original material, tint and transition are unknown.
6. **Fisheye reach:** profile media tabs are the real port consumer. The original custom horizontal button-row class has not been identified/recreated. No claim is made for other button rows or bubble distortion.
7. **Scroll behavior:** only ordinary bubble nodes consume the effect. Freeform sticker/service-message nodes, exact original offset accumulation and native spring timing are not ported. The recovered clamps/scale constants are used with a bounded clean-room spring, not a replacement scroll physics engine.
8. **Particles:** snow/leaf drawings are clean-room, not recovered PNGs. Trajectories/lifetimes/emitter geometry differ. Reduce Motion disables particles entirely rather than the original threefold birth-rate reduction. The original battery-level cutoff is not reproduced; Low Power Mode and lifecycle gates are. Mode 0 covers the app-root view, not other UIKit windows/system sheets. Mode 1 covers the chat wallpaper, with visibility teardown. Extra particle kinds mentioned generically in help are not invented.
