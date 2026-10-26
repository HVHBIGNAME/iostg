# Remaining Whitegram implementation work

Updated 2026-10-26 for the build-34652 client integration.
**The client is not feature-complete.** The recovered catalog still
has **1 row without a UI route**: `hideOthersCustomMessageStyle`.
This is a routing count, not a percentage of implemented behavior. Reachable
screens also require behavioral/parity validation; the original 333-row audit in
`FEATURE_COVERAGE.md` is historical and cannot be used as current completion data.

## Unconnected catalog rows

- [ ] `hideOthersCustomMessageStyle`

This row depends on other-user style delivery/cache, which is absent in the
current client. The help row is connected. No writable no-op toggle is provided.

## Build 34652 validation

Account profiles, local pins, navigation/backgrounds, previews, client/device
controls, presence/read capture, visual effects, feed and classic adapters now
have installed consumers. See [BUILD_34652.md](BUILD_34652.md) and the corresponding
`*_PORT.md` documents for their actual contracts and original-parity gaps.

- [x] Apple SDK release/simulator compilation of the entire increment — [run 40275611466](https://github.com/HVHBIGNAME/iostg/actions/runs/40275611466).
- [x] Fresh install and relaunch in the iOS 26.5 simulator, plus login connectivity probe.
- [ ] Device checks for account switching, filter deletion, pin ordering and media lifecycle.
- [ ] Original visual/interaction comparison, including inline feed media and classic layout.
- [ ] Original private-settings absent-key migration/tombstone semantics.
- [ ] Remaining badge variants and remote custom-message style delivery.

The anti-scam consumer reads the existing legacy cache. The previous backlog's
claim that a signed-database verifier exists was not substantiated; see
[REMAINING_PRESENTATION_PORT.md](REMAINING_PRESENTATION_PORT.md).

## Earlier build evidence and completion gates

Build-34646 sources connect `showOriginalTelegramIcons`, `customSettingsIcons`,
`inAppVibration`, `showMutualContactsCard` and `showRegistrationDateCard`.
The 379-test Python suite passes without skips; native build and device checks
are pending. Registration's original persistent caches and known-user prefilter
remain unimplemented. The feedback increment covers the recovered normal-send
hook, not every action mentioned in the original help text. See
[BUILD_34646.md](BUILD_34646.md) for evidence and verification boundaries.

`highlightMentions` and `roundProfileActionButtons` now have runtime consumers
and routes in the build-34643 source increment. Native compilation and clean
simulator launches passed in build 34645; device verification and
exact profile-layout comparison are pending; see
[APPEARANCE_DETAILS_PORT.md](APPEARANCE_DETAILS_PORT.md). These rows are not
counted as unconnected, but are not certified as full parity.

`onlineHistoryEnabled`, `onlineHistoryView` and `onlineHistoryClear` now have
source consumers and UI routes. They are **not marked parity-complete**:
device checks, capture-policy comparison and
original archive migration remain pending. See [ONLINE_HISTORY_PORT.md](ONLINE_HISTORY_PORT.md).
The change is included in [build 34642](BUILD_34642.md), whose native CI suites
and release compilation passed.

For each operational row, establish its recovered behavior and stored types,
connect its control to an installed consumer, verify persistence and refresh,
test repeatable source assembly, compile natively, then exercise the actual
device/network interaction. Do not replace a missing consumer with a writable
preference or mark a whole family complete because its settings screen opens.

The current diagnostic build adds automatic technical crash/hang/service reports
through a private inbox. Receiver delivery has a successful HTTPS-to-GitHub smoke
test. Device capture, symbolication and all existing device checklists remain
separate verification tasks.
