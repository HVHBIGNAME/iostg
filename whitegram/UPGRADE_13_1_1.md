# Telegram 13.1.1 migration

Candidate build: **34653**. Device IPA and simulator verification are pending.
The verified download remains build 34652 until the new build passes.

## Inputs

- Official tag: `release-13.1.1`.
- Commit: `fb0e62ba8a147f0821da6aa63c09da7d79a10111`.
- App Store lookup: version `13.1.1`, published `2026-10-22T18:45:59Z`.
- Upstream `versions.json`: app `13.1.1`, Xcode/deploy Xcode `27.1`, macOS `27`,
  Bazel `9.2.0:dd466352a3e4d3581b8898740ee1ff208866ccbe25f8d367c5dcb950219587e6`.
- GitHub runner: `xcode-27`, whose published inventory includes Xcode 27.1.
- Public WhiteGram overlay remains `db18308774f863074278feedc4df4507b0fb174e`
  against `release-12.6.2`.

## Adaptations

- `public_resolutions_131.py` keeps the current framework exports, Rust login key
  validation, proxy observer, News availability gate, vertical tabs and crossfade.
- The removed folder navigation renderer is replaced by a native
  `NavigationBarComponent.Button` using the bundled folder icon and existing action.
  The account switcher uses the same new button contract.
- Classic headers attach to `NavigationBarNode` and its transition-owned content;
  local tab refresh carries the upstream News state.
- Edit capture and plugin events use `mergedServerMessageUpdate`, preserving the
  server-update reconciliation before recording prior history.
- Video settings preserve camera-mode selection and verified local-file storage;
  processed voice-video output avoids caching the unused unprocessed video.
- Return-key handling reaches both implementations of `RichTextEditor`, including
  the InputDec surface gate, hardware/IME exclusion and the real keyboard's return type.
- Generated TelegramApi sources are build outputs now. Schema checks use the TL
  declaration rather than a checked-in `Api43.swift` filename.

## Module boundaries

The old fork's import reconciliation used to re-add Postbox and TelegramApi to
modules that upstream had migrated. `telegram_131_boundaries.py` removes these
reintroduced imports and dependencies. TelegramApi stays private to TelegramCore.

The explicit Postbox exceptions in that file retain existing Whitegram storage
contracts: off-page local-pin views, raw message/presence consumers, post-commit
plugin scopes, local history retention, notification enrichment and staged media.
They are enumerated paths, not a directory wildcard or a disabled checker. The two
additional client packages are SettingsUI and ChatMessageItemImpl. The upstream
`PostboxImportCheck.py` continues to check unexpected and stale entries. These
legacy adapters still need a separate engine-facade migration.

## Verification

Record the final source revision, CI run, IPA digest and simulator evidence here
after successful verification. Source parsing alone does not validate native APIs,
visual transitions, logged-in workflows or physical-device installation.
