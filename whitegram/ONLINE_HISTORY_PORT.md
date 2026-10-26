# Contact online history — Beta 3.2 original v2 compatibility

Target source: Telegram `release-13.0.0`,
`f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`.
See [HISTORY_PORT.md](HISTORY_PORT.md) for parent integration, spy consumers,
the verified original IPA identity and executable verification commands.

## Fresh shipped-artifact observations

The supplied Beta 3.2 IPA SHA-256 was reverified as
`5cf287812de7707dd21256281e645c29a9a5c0da3f66910746254842fce5ffbf`.
Local wgtool inspected TelegramCoreFramework ARM64 bytes:

- `SGOnlineHistoryStore.key` at `0x300b8` constructs `wg_onlineHistory_v2`
  (cstring at `0xe98720`). `allEntries` `0x211d58` obtains UserDefaults Data,
  JSON-decodes an array of `SGOnlineHistoryEntry`, and caches it. There is no
  account/version envelope or UUID field in the original format.
- Initializer `0x21136c`, decoder `0x21162c`, encoder `0x2119f8` establish
  `peerId`, `peerName`, optional `peerUsername`, `isOnline`, `timestamp`, optional
  **`serverTimestamp`** and `isContact`. The decoder uses `decodeIfPresent` for
  `isContact`; an older record without it decodes false. It is retained as unknown
  historical membership rather than silently dropped or converted to a contact.
- The recovered 3.1.1 `append` (`0x1ea09c`) suppresses repeated online state and caps
  2000 rows. Beta 3.2 retains the store/append shape (`0x211f20`) and 50-row UI
  page-size symbol. Original capture hooks `0x39ae20`, `0x39aeb4` in function
  `0x396808` test `onlineHistoryEnabled`.

These are static artifact observations, not an iPhone comparison.
`tests/test_history_original.py` rechecks the hash, string, symbols and optional
date/contact decode calls against the exact original bytes.

## Implemented migration and capture

- Existing `ONLINE_HISTORY_RUNTIME_FILES` remains unchanged. Copy the updated
  store/capture/controller in the same overlay installation pass.
- `apply_online_history_patches` records API-user and explicit-status inputs only
  after Telegram's accepted presence merge. Min-status/own-ID handling and native
  last-activity merging remain. It composes with `apply_spy_patches` in either order.
- New capture still requires enabled **contact** membership and explicit
  online/offline status. Offline `wasOnline` is retained separately as
  `serverTimestamp`; `timestamp` remains local receipt time. Online expiry values
  are not treated as last-seen timestamps. Privacy-coarse statuses, typing and
  expiry timers do not synthesize events.
- The controller offers **Import original online history** when
  `wg_onlineHistory_v2` exists. Its confirmation names the exact destination
  account. `migrateOriginalForThisAccount` bounds/decodes/validates the entire array
  before loading or merging the destination archive. Invalid/self/non-user peer
  IDs, malformed dates/types and oversized strings fail without changing it.
- Migration preserves original local/server times, name, username and contact
  flag. It gives retained rows UUIDs once, matches exact observations on replay,
  merges chronologically, caps the latest 2000, and reports newly retained rows.
  The shared original bytes remain unchanged for recovery and explicit reassignment.
- The current `WhitegramOnlineHistory.v1.<accountId>` envelope reads old rows without
  serverTimestamp and exports/loads the optional addition. Existing modern archives
  must have the matching account ID and unique UUIDs; corrupt archives are preserved
  until the existing explicit clear action.
- UI filtering/pagination continues to use receipt time. Offline rows can display
  the separate original server last-seen date. Search, per-peer/date filters,
  live updates, 50-row pages and full-account clear remain implemented.

## Verification executed

- Six focused Python/source tests passed using the read-only assembled 13.0 source.
- Spy tests verify both patch orders produce identical bytes, replay writes nothing,
  late drift aborts all patch writes, and native read/presence source parses.
- Ten online-history XCTest cases passed in the production Foundation runner under
  WSL Swift 6.4. New cases cover old-v2 optional fields/server time, exact replay/
  reload, explicit account isolation and malformed migration preserving both stores.
- The combined Foundation runner passed **51 tests**. Three original-IPA checks
  separately passed under the local recovery venv with fresh hash verification.

## Remaining boundaries

The original shared archive cannot identify its account, so migration requires
explicit binding rather than assigning it to the first active account. The parent
owns logout cleanup and preference/account routing. UI and Postbox adapters still
need the parent's macOS compilation/device checks. No events are reconstructed
while the client receives no updates. Online history records contact transitions;
the requested spy consumers are separately described in HISTORY_PORT.md, with the
shipped-disabled original getters clearly distinguished from new implementation.
