# Telegram 13.1.2 migration

Updated **2026-11-06**. Candidate build: **34654**. Source integration has passed
the local checks below. Native release compilation, IPA verification and simulator
checks are pending. The verified download remains [build 34652](BUILD_34652.md).

## Inputs

- Official tag: `release-13.1.2`, latest official release tag checked on this date.
- Commit: `279f89e4d4f63f17227bf877dc3d8990f22ecd58`.
- Previous pin: `release-13.1.1`, `fb0e62ba8a147f0821da6aa63c09da7d79a10111`.
- [Upstream comparison](https://github.com/TelegramMessenger/Telegram-iOS/compare/release-13.1.1...release-13.1.2):
  41 changed files, including media handling, supplementary-account updates,
  Siri message reading, bot storage and wallet UI/state.
- `versions.json`: app `13.1.2`, Xcode/deploy Xcode `27.1`, macOS `27`,
  Bazel `9.2.0:dd466352a3e4d3581b8898740ee1ff208866ccbe25f8d367c5dcb950219587e6`.
- Workflow runner: `xcode-27`. `.github/actionlint.yaml` declares this existing
  runner label, also recorded by the previous CI run.
- Public overlay: `db18308774f863074278feedc4df4507b0fb174e`, base `release-12.6.2`.

## Integration

`upstream.json` and the workflow matrix select the same official commit.
`public_resolutions_131.py` explicitly supports both pinned 13.1.1 and 13.1.2
revisions; `port_public.py` routes each to the reviewed 13.1 resolver. Earlier
13.1 adaptations and module-boundary rules remain documented in
[UPGRADE_13_1_1.md](UPGRADE_13_1_1.md).

The fresh 13.1.2 port considered **607 entries**, applied **593 files** and had
no unresolved conflicts. It used **45 reviewed resolutions**. The compatibility
installer added 84 imports and 167 BUILD dependencies. Those are assembly counts,
not a count of completed features.

Both revisions have merge regression coverage for login, News, tabs, local pins
and native navigation. The 13.1.2 suite also verifies preservation of the upstream
`ignoresShortSentMessages: supplementary` / `ignoresShortSentMessages: true`
guards in `TelegramCore/Sources/Account/Account.swift`.

## Previous build failure

[Run 40428640490](https://github.com/HVHBIGNAME/iostg/actions/runs/40428640490)
reported a Display error from the RAM overlay using the removed
`WindowLayout.safeInsets` member. The installer now uses
`windowLayout.reservedArea.safeInsets.left`, including when migrating an already
installed old hook. Tests cover clean installation, migration and replay.

TelegramCore also failed, but its **8,631,449-byte stderr** was suppressed by Bazel;
its underlying compiler errors remain unresolved. Both release and simulator
commands now pass `--experimental_ui_max_stdouterr_bytes=16777216`. On failure,
the workflow uploads `WhiteGram-compiler-diagnostics-${{ github.sha }}` from the
configured Bazel user root's action stderr files, with 14-day retention.

## Local verification

| Check | Result |
| --- | --- |
| Main Python suite against assembled 13.1.2 | 515 tests, 0 failures, 8 skipped |
| Voice suite | 22 passed |
| Player suite | 10 passed |
| JavaScript plugin suite | 60 passed |
| Assembled Swift parser comparison | 549 files, no new diagnostics |
| Plugin Swift parser | 21 files passed |
| History/plugin hook composition | Both orders and replay passed; 9 source files checked |
| Service source checks | 18 production + 8 test Swift files parsed |
| Settings-transfer source checks | 10 production + 3 test Swift files parsed |
| Ruff on changed Python files | Passed |
| Workflow validation | actionlint 1.7.11 passed with the declared runner label; external ShellCheck not run |
| Whitespace validation | `git diff --check` passed |

After the final Python cleanup, the affected Telegram, system and feed/classic
suites were rerun: **21 + 15 + 5 tests passed**.

The eight skips are one POSIX-root-alias test, three original-history binary tests
requiring the separate wgtool environment, and four original-icon recovery tests
requiring `WHITEGRAM_ORIGINAL_AUDIT`. They are not counted as passed tests.
The separate reference comparison is recorded in [REFERENCE_8_1_1.md](REFERENCE_8_1_1.md).

The feed/classic fixture now rewinds its own installed hooks in scratch staging
before testing initial installation, exact reversal and malformed anchors.
`WHITEGRAM_FEED_SOURCE` is enabled in CI, so these five tests run against the
assembled tree instead of being skipped.

The exact CI check commands and environment are in `.github/workflows/build.yml`.
Local reports are retained under
`C:\Users\Pisun4ik\AppData\Local\Temp\opencode\whitegram-port-13.1.2\`
as `report.json` and `syntax.json`.

## Remaining release checks

- [ ] Publish the candidate revision and run macOS CI.
- [ ] Resolve any TelegramCore errors using the complete compiler diagnostics.
- [ ] Pass configured native Swift suites and full device/simulator release builds.
- [ ] Verify the resulting IPA, source revision, identifiers, resources and symbols.
- [ ] Confirm simulator fresh-install/relaunch and requested login connectivity.
- [ ] Record the CI URL and IPA SHA-256 before replacing the verified download.

Physical-device and signed-in feature checks remain separate. The migration does
not close the behavioral gaps listed in [CURRENT_BACKLOG.md](CURRENT_BACKLOG.md).
