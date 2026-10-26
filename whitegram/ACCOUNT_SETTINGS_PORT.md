# Account settings profiles

The `accountSettings` catalog action and Accounts screen open
`WhitegramAccountSettingsController`. Each account has a switch: on uses the
shared profile, off selects its private profile. The first private profile copies
the current shared configuration; returning to shared mode retains the private
profile for later use. AccountRecordId values stay exact signed Int64 values.

`WhitegramPreferences` retains the shared canonical JSON in
`WhitegramSettingsState.v1` and stores private JSON snapshots plus binary
property-list mirror snapshots in `WhitegramAccountSettings.v1`. The primary
account signal selects a profile before constructing its application UI. Raw
`wg_*` and public-fork stores are projected before notification delivery, and
absent mirrors are removed when switching. Changes to an inactive profile do
not replace the active raw stores. Existing canonical consumers resolve the
selected primary profile, including background consumers using the original
global active-account convention.

Plugin/runtime permission state, migration markers, active-account metadata,
provider API keys, connection statuses and the independently account-indexed
local Premium presentation store remain shared metadata. These entries are not
copied into private configuration. Profile stores are bounded to 16 MiB and
1000 accounts; malformed stores are refused without replacement.

## Transfer

Import/export captures an explicit shared/private scope when opening its screen.
Switching accounts or changing shared/private mode while a document picker is
open does not redirect the import. Partial imports preserve absent settings.
Public chat/tab/story/folder mirrors are prepared using that profile's stored
snapshot. Device-local Keychain items use `settings-v1` for shared settings and
`settings-v1-account-<id>` for private settings. Portable files keep the existing
allowlisted v1 format and contain no profile IDs or credentials.

## Original evidence

Beta 3.2 Core SHA-256:
`9908ba0fcf3782f6f7da9a3b4f82b941cc95c952ba1b631cb33451747e96e198`.
Focused disassembly used the existing wgtool/Capstone environment against the
original IPA. `accountUsesSeparateSettings` is at `0x21d40c`, its setter at
`0x21d5fc`, and the active-account key resolver at `0x21df5c` appends
`_account_<decimal id>`. The setter enumerates existing settings on first
activation. Mode keys are `wg_separateAccountSettings.v1` and
`wg_privateSettingsAbsent.v1`; the event literal is
`wg_accountSettingsModeDidChange`. Zero account IDs are rejected.

The port reads the original decimal mode dictionary and known suffixed primitive
settings when creating profiles. Original absence-tombstone semantics and the
complete original key exclusion list have not been reproduced. The new bounded
snapshot envelope and retention rules are explicit port behavior.

## Verification

- Foundation executable compiled with Swift 6.4 in Swift 5 mode and
  `-warnings-as-errors`: two-account isolation, exact Int64 limits, raw/public
  mirrors, inactive imports, retained profiles, new-process restoration,
  primitive legacy migration, secret preservation and malformed-store refusal.
- 30 existing archive/store XCTest cases passed on WSL using the actual public
  fork settings models. Apple Security and UIKit tests require macOS.
- All five installer composition checks passed, including full-sequence replay,
  stage replay, registration completeness and no new Swift parser errors.
- The top-level suite ran 460 tests with zero failures; 63 environment-dependent
  cases were skipped with only `WHITEGRAM_ASSEMBLED_SOURCE` configured.
- Previously prepared interface/device runtime manifests are now installed. The
  corresponding source adapters passed 30 interface policy checks, 23 local
  Premium fixture checks and 50 device/camera boundary checks.

Commands:

```text
python -B whitegram/tests/settings_transfer/run_account_checks.py --scratch-parent <existing-temp> --assembled-source <assembled>
python -B -m unittest discover -s whitegram/tests -p test_full_composition.py -v
```

The account Foundation checks are registered in native CI. No new iOS IPA or
device UI validation was produced by this Windows session.
