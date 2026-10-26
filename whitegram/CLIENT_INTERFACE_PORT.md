# Client interface port

## Delivered and integration contract

`client_interface_patches.py` supplies the independent staging entry point
`client_interface_patches(patches: SourcePatches)` and writing entry point
`apply_client_interface_patches(root: Path) -> dict[str, list[str]]`.
The expected target is the assembled Telegram 13 overlay, original source pin
`f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`. Exact anchors, rather than a guessed
version fallback, determine admission. Apply after baseline appearance/profile
patches: those provide the two explicit appearance-refresh anchors used here.

The installer owner must copy `cleanroom/` files using
`CLIENT_INTERFACE_RUNTIME_FILES`, then invoke the patcher. Existing target
source globs include these destinations. `CLIENT_INTERFACE_REQUIRED_DEPENDENCIES`
is `{}`: each destination already has the dependencies used by its new files.

### Exact runtime map

| Source basename | Destination |
|---|---|
| `WhitegramClientInterfacePolicy.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramClientInterfacePolicy.swift` |
| `WhitegramClientInterfaceSettings.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramClientInterfaceSettings.swift` |
| `WhitegramClientInterfaceTheme.swift` | `submodules/TelegramPresentationData/Sources/WhitegramClientInterfaceTheme.swift` |
| `WhitegramClientInterfaceReactionGlow.swift` | `submodules/Components/ReactionButtonListComponent/Sources/WhitegramClientInterfaceReactionGlow.swift` |
| `WhitegramClientInterfaceProfileUpdates.swift` | `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/WhitegramClientInterfaceProfileUpdates.swift` |
| `WhitegramLocalPremiumPolicy.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramLocalPremiumPolicy.swift` |
| `WhitegramLocalPremiumPresentation.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramLocalPremiumPresentation.swift` |
| `WhitegramLocalPremiumController.swift` | `submodules/SettingsUI/Sources/WhitegramLocalPremiumController.swift` |
| `WhitegramAccountStripOrder.swift` | `submodules/TelegramCore/Sources/Settings/WhitegramAccountStripOrder.swift` |
| `WhitegramAccountStripItem.swift` | `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/WhitegramAccountStripItem.swift` |

### Boolean capability bindings

`CLIENT_INTERFACE_BOOLEAN_CAPABILITIES` is an explicit consumer-availability map.
True does **not** assert original pixel or full feature-family parity.

| Key | Boolean | Consumer / qualification |
|---|---|---|
| `newChatListUI` | `true` | Rounded, separated chat row surfaces; safe-area/content insets, selection highlight; renewed presentation identity on toggle |
| `newChatHeaderStyle` | `true` | Both title-rendering implementations get updated name/status layout and no-glass header background; live refresh |
| `classicInterface` | `false` | Header no-glass OR gate implemented; full Telegram 11.15 tabs/folders/composer/panels restoration remains missing |
| `oledMode` | `true` | Dark-only black root/list/chat-list/input surfaces; theme rebuilt on preference changes |
| `reactionButtonGlow` | `true` | Colored pill shadow, original opacity `0.62`, radius `7`, zero offset; tags excluded; disable clears opacity live |
| `roundProfileButtons` | `true` | Horizontal account avatars plus existing visible edit/add actions, badges, account switch, drag reorder, accessibility reorder/account menu |
| `localPremium` | `true` | Local own-profile badge, name/profile color/background emoji/status and functioning local editor; no global entitlement substitution |
| `unlimitedPinnedChats` | `false` | No complete persistent overflow projection/loading/reorder path delivered |

`CLIENT_INTERFACE_REQUIRED_BINDINGS`:

```python
{"localPremium": "WhitegramLocalPremiumController(context: context)"}
```

Bind the original `localPremium` menu destination to that controller in the
shared menu/capability layer. The native own-profile status/color buttons already
route to this controller while local Premium is enabled. Other true keys use
their existing boolean rows and `WhitegramPreferences` writes.

The writing wrapper returns these exact hook inventory keys:
`newChatListUI`, `client-interface-live-list`, `newChatHeaderStyle`,
`classicInterface-header`, `oledMode`, `oledMode-live-refresh`,
`reactionButtonGlow`, `roundProfileButtons`, `localPremium`,
`client-interface-live-profile`. The `localPremium` hooks span settings row
construction, settings actions, profile header rendering, and direct profile
status/color action routing. Hooks target 11 existing Swift source files.

## Persistence and boundaries

Interface toggles read strict JSON booleans through the shared preferences API.
Malformed numeric/string switches do not activate these consumers. Each signal
registers before its initial emission and disposes its observer.

Local Premium's five fields are stored under
`clientInterfaceLocalPremiumAccounts[decimal AccountRecordId]` in the canonical
settings snapshot. Exact Int64 parsing avoids emoji-ID rounding. Colors require
nonnegative Int32 values; emoji IDs require positive Int64 values. Missing fields
fall through to real profile data. Reset removes this account's local overrides;
disable retains the configuration and returns the original peer object.
Malformed nested stores are refused without replacing their saved bytes.

`WhitegramLocalPremiumPresentation.peer` creates a detached own-user value **only
inside `PeerInfoHeaderNode.update`**. Other users, channels and nil stay unchanged.
Engine data, Postbox peer records, billing, payment requests, subscription state,
and server limits do not receive that presentation value. Local editor routes
intercept direct own-profile status/color actions, preventing them from calling
stock update-account RPCs while this local mode is active.

Account reorder uses one AccountManager transaction to replace only
`.sortOrder` attributes, preserving other attributes and account IDs. Membership
is revalidated inside the transaction; a join/logout/import during a drag aborts
it. The strip observes AccountManager's actual order, including the primary
account, so a reorder survives reopening and the current account is not forcibly
moved back to the first slot. Cancelled gestures do not commit. Existing hidden
edit/add actions are filtered before strip construction.

## Precise replay and failure handling

Every edit is exposed as `ClientInterfaceEdit` through
`client_interface_edits()`. Missing, ambiguous, duplicated or mixed pre/post
anchors raise. Staging restores `original`, `pending`, and `features` on failure,
including a supplied transaction's already-staged unrelated edits.

The writing wrapper reads byte preimages, rejects symlink/root escapes, stages
all edits, prepares sibling replacement/backup files, preserves CRLF/LF and
modes, checks concurrent preimage changes, then uses `os.replace`. An ordinary
I/O failure rolls committed files back to exact preimages and cleans temporary
files. If rollback itself fails, retained backup paths are reported and the
preimages are kept for recovery. This is failure rollback, **not crash-atomic multi-file publication**;
a process/power failure or simultaneous reader can observe an intermediate
commit. Use the staging API inside the parent owner's larger preflight transaction
when composing modules. Runtime file installation itself remains the caller's
responsibility.

## Original evidence

Original IPA SHA-256:
`5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.
UI framework SHA-256:
`7f64950144cc75631ceb9cc9365cd4d802d583e5315ee63498829a1c72cb3ac3`.

Read-only recovery: `whitegram-rebuild/recovered-3.2/{interface-resolved,theme-resolved,native}`.
Fresh focused disassembly is in the approved scratch directory
`C:\Users\Pisun4ik\AppData\Local\Temp\opencode\client-interface-evidence`;
its `evidence.json` records original bytes and function bounds (52 Core,
316 UI functions). This export was generated using the existing wgtool environment.

Validated UI call sites:

- `0x183e48` updated header; `0x183e58` classic header. The branch implements OR.
- `0x1945d84` chat-list appearance consumer.
- `0x9a4504` account-strip preference in settings item construction.
- `0x31e3378` reaction-glow consumer; `0x31e3400` loads float `0.62` from
  `0x556d1e4`, `0x31e3434` sets radius `7`.
- `0x2a3f0` local Premium gate, `0x2a408/410/418/420/428` its five profile fields,
  `0x2a44c` calls `WGProfileColorManager.setColor(...isLocalPremium...)`.
- `wgApplyOledTheme` at `0x38cb178`, byte SHA-256
  `381257687caab0a17f3aaac60435ec4b1ec471cd57e09bd62e43eecad47943b9`.
  The dark guard and black/`0d0d0d`/`0f0f0f` surfaces are visible in disassembly.

Recovered `wh.newChatListUI`, `wh.roundProfileButtons`, `wh.newChatHeaderStyle`,
`wh.classicInterface`, `wh.oledMode`, `wh.reactionButtonGlow`, `wh.localPremium`
localization provides the intended behavior descriptions. Exact card/header
geometry is a cleanroom design; its pixel match is unverified. Fresh direct
branches for `unlimitedPinnedChats` found settings getter sites, which do not
establish an original persistent local ordering model.

## Actual verification

Python: `whitegram-check-env/Scripts/python.exe -B -m unittest discover -s
whitegram/tests -p test_client_interface_patches.py -v`, with
`WHITEGRAM_CLIENT_SOURCE` set to the read-only assembled target and
`WHITEGRAM_CLIENT_SCRATCH` set to the approved scratch parent: **10 tests passed**.
Coverage includes each missing anchor, late failure with no writes, duplicate/
mixed replay, exact idempotence/newlines, registry boundaries, and simulated
third-file I/O failure with exact rollback, failed-rollback backup retention,
concurrent-owner modification, composed-owner staging and repeated card-layout
parameter preservation. Passed on assembled source and standalone fixtures.

`tests/client_interface/run_checks.py --source <assembled> --scratch-parent
<approved-temp>`: **21 Swift files parsed**, exact replay passed;
WSL `/opt/swift/usr/bin/swiftc` 6.4 compiled and ran **30 Foundation policy checks**
and **23 local Premium storage/presentation checks** with `-warnings-as-errors`.
The latter compile the actual shared preferences and new presentation code
against explicit small Postbox/peer API fixtures. They verify detached
presentation, other-user exclusion, account isolation, exact IDs, disable/reset,
and malformed-store preservation. They are not an iOS/Telegram module typecheck.

`tests/client_interface/check_original.py` with
`whitegram-rebuild/.venv/Scripts/python.exe`: **11 original call sites, IPA/UI
digests, original glow opacity and recovered OLED function bytes passed**.
The requested check env lacks Capstone; the existing wgtool venv supplied it.

## Real remaining blockers

- Full Apple SDK/Bazel typecheck and simulator/device UI checks: scrolling,
  selection/reveal transitions, dynamic type, title clipping, drag accessibility,
  theme toggling, and emoji resource rendering remain unverified.
- Classic mode implements only header material; no claim of Telegram 11.15
  shell restoration. Its capability stays false.
- Unlimited local pins need account/group/filter-scoped persistence, loading
  pinned peers outside paginated views, local sort indices independent of the
  UInt16 server pin index, all pin/unpin entry points and mixed server/local
  reorder/sync semantics. No raised limit or incomplete ordering toggle is added.
- Local Premium is own-profile presentation, not every original local interface
  privilege or cross-chat name decoration. Recovery of original saved defaults,
  legacy `wg_lp*` account ownership/migration, resource picker parity and custom
  color palettes remains open. Current local editor accepts available color/file
  IDs; server-provided palette fallback can affect unknown color indices.
- Cards intentionally retain stock editing/inline/community/custom-message row
  layouts; exact original row/header geometry and all menu localization remain open.
- Main-menu route/capability and runtime-file installation are required parent
  bindings listed above. No installer, existing menu/preferences/catalog,
  workflow, account/history/media/plugin patch files are changed here.
