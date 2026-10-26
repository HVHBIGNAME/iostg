# CLIENT camera, device name, and delayed send (Beta 3.2)

## Evidence

Reference IPA SHA-256: `5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.
Telegram reference pin: `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`.
Existing evidence: `whitegram-rebuild/recovered-3.2/{native,composer-resolved,interface-resolved}`.
Focused exports: `C:/Users/Pisun4ik/AppData/Local/Temp/opencode/whitegram-client-evidence-32/evidence.json`.

* Camera getter: TelegramCore `0x22b504`; consumer TelegramUI `0xbdd38`.
  The enabled video path constructs a front/back picker initialized from
  `videoMessageCamera` (`0xbdf90`) and writes the selection through that setter
  (`0xbe278`) after checking the recording request identity. The microphone-end
  consumer also consults the bool (`0x2b2db4c`). Port locks the accepted selection,
  ignores stale authorization/selection callbacks, and propagates the selected
  position through camera construction to the existing recording compositor fix.
* Device editor: UI `0x1106254`, `trimmingCharacters(in: .whitespacesAndNewlines)`
  followed by `fakeDeviceName` setter at `0x1106308`.
* MtProtoKit SHA-256: `1112151dc4b88d9f3b46a4390a0c816a293149f885991b46bffff7b2c45d7da9`.
  `MTApiEnvironment.initWithDeviceModelName:` (`0x11828`) remains the normal
  supplied-model/platform fallback. `MTRequestMessageService.decorateRequestData:`
  (`0x48594`) reads `wg_fakeDeviceName` (`0x4891c`), checks NSString (`0x48950`),
  tests length (`0x48970`), falls back to deviceModel (`0x48988`), and serializes
  the selected string (`0x489a0`). This is an initConnection field override;
  system/app/language/proxy fields and initialization hash are unchanged.
* Deferred send: UI `0xaa51c` getter, `0xaa59c` adds **12 seconds** to the
  current epoch timestamp, `0xaa918..0xaa938` builds a schedule attribute,
  then calls native enqueue. Media `0x1db740..0x1db870` uses a 12/20 second branch.
  Composer consumers `0x263bf0`, `0x266f08`, `0x26a1a4`, `0x26d7b0`,
  `0x271dac`, `0x2762d0` additionally drive the input-panel cancellation/countdown
  path; `0x26d848` and `0x271e44` load 12.0. Recovered localization
  `wh.deferredMessages` explicitly describes cancellation within 12 seconds.

## Integration handoff (shared installer/capabilities owned by parent)

* Existing `MEDIA_RUNTIME_FILES` and `apply_media_camera_patches(root)` now include
  the original `chooseCameraBeforeRoundVideo` consumer. Canonical and legacy
  `wg_chooseCameraBeforeRoundVideo` are read by `WhitegramMediaSettings`.
  Register boolean `chooseCameraBeforeRoundVideo -> chooseCameraBeforeRoundVideo`;
  localized title `s.chooseCameraBeforeRoundVideo`. Media controller already exposes it.
* Import `DEVICE_RUNTIME_FILES`, `apply_client_device_patches` from
  `client_device_patches.py`; install each cleanroom source at its mapped destination
  and invoke the patcher. Existing BUILD source globs/dependencies cover these modules.
* Boolean binding `deferredMessages -> deferredMessages`; title `s.deferredMessages`,
  description `wh.deferredMessages`.
* Value binding `fakeDeviceName`: open `whitegramDeviceSettingsController(context:)`.
  It edits the real canonical value and primitive MTProto mirror, trims on save,
  and supports clearing. Title `s.fakeDeviceName`, description `wh.fakeDeviceName`.
* Patcher report: `fakeDeviceName` -> MTRequestMessageService.m;
  `deferredMessages` -> ChatController.swift, ChatControllerLoadDisplayNode.swift,
  ChatControllerMediaRecording.swift. `client_device_patches(patches)` supports
  in-memory composition; wrapper applies only after every counted anchor validates.

## Implemented send behavior

Ordinary cloud sends get one native `OutgoingScheduleInfoMessageAttribute(now + 12)`.
Composer batches (including multi-source forwards), regular media, recorded audio,
video messages, and inline-bot results all reach it. Existing explicit schedules,
scheduled-subject commits, secret chats, paid/postponed sends and view-once content
are excluded. User undo deletes only the matching scheduled messages, follows
correlation remapping across local/server IDs and late ack application, stops at
the original deadline, and never turns a late undo into deletion of a sent message.
Native scheduling persists across chat dismissal/app termination. Current undo UI
is an actual cancellable timeout overlay, rather than the original panel animation.

## Checks and remaining gaps

`test_media_camera_patches.py`: pristine/assembled camera patching, replay,
selected-side propagation, authorization identity, cancellation, counted-anchor
failures and existing capture/metadata consumers.
`test_client_device_patches.py`: pristine/assembled replay, camera/read-action/voice
composition, real scratch-tree write/replay, device field placement, and negative anchors.
`tests/client_device/run_checks.py`: Swift 6.4 on WSL compiles production settings
and deferred consumer with warnings-as-errors and typed Postbox/Signal boundary
fixtures; executes 50 policy/state/boundary checks; parses 16 runtime/patched files.

No Apple SDK build or real iOS/server interaction was run on this Windows host.
Fixture signals exercise deterministic boundary ordering, not actual networking.
The original special **20-second media branch**, exact input-panel countdown/picker
animation, and deferred eligibility predicates beyond the decoded option checks
remain uncertain. Exclusions for paid/view-once/secret sends are conservative port
policy, not claimed recovered equivalence. Original per-account low-level defaults
routing remains with the parent's account/preferences work. Shared registration is
intentionally supplied as a handoff and has not been applied by this worker.
