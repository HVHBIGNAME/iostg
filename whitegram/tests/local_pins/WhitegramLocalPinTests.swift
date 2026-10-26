import Foundation

@main
enum LocalPinTests {
    static var checks = 0
    static func check(_ value: Bool, _ label: String) {
        checks += 1
        if !value { fatalError(label) }
    }
    static func rejects(_ label: String, _ body: () throws -> Void) {
        checks += 1
        do { try body(); fatalError("did not reject: " + label) } catch {}
    }

    static func main() throws {
        var state = WhitegramLocalPinState()
        let eligible: Set<Int64> = [1, 2, 3, 4, Int64.max, Int64.min]
        try state.toggle(3, server: [1, 2], eligible: eligible)
        check(state.effective(server: [1, 2], eligible: eligible) == [3, 1, 2], "local before cloud")
        try state.toggle(1, server: [1, 2], eligible: eligible)
        check(state.effective(server: [1, 2], eligible: eligible) == [3, 2], "local unpin hides cloud")
        check(state.hidden == [1] && state.local == [3], "separate ownership")
        try state.toggle(1, server: [1, 2], eligible: eligible)
        check(state.effective(server: [1, 2], eligible: eligible) == [1, 3, 2], "cloud re-pin moves first")
        try state.reorder([2, 3, 1], expected: [1, 3, 2], server: [1, 2], eligible: eligible)
        check(state.effective(server: [1, 2], eligible: eligible) == [2, 3, 1], "mixed reorder")
        check(state.effective(server: [2, 4], eligible: eligible) == [2, 3, 4], "remote removal/addition")
        check(state.effective(server: [3, 2], eligible: eligible) == [2, 3], "server local dedup")
        check(state.effective(server: [1, 2], eligible: [1, 2]) == [2, 1], "moved/deleted pin hidden")
        check(state.effective(server: [1, 2], eligible: eligible) == [2, 3, 1], "restored peer retains rank")
        rejects("stale reorder") { try state.reorder([1, 2, 3], expected: [1, 3, 2], server: [1, 2], eligible: eligible) }
        rejects("duplicate reorder") { try state.reorder([2, 3, 3], expected: [2, 3, 1], server: [1, 2], eligible: eligible) }
        rejects("partial reorder") { try state.reorder([2, 1], expected: [2, 3, 1], server: [1, 2], eligible: eligible) }
        rejects("unavailable pin") { try state.toggle(99, server: [], eligible: eligible) }
        try state.toggle(3, server: [1, 2], eligible: eligible)
        check(state.local.isEmpty, "unpin local removes membership")

        // Independent Int ranks well past the stock UInt16 index range.
        var large = WhitegramLocalPinState()
        large.local = Array(1...70000).map(Int64.init)
        large.order = large.local.reversed()
        let all = Set(large.local)
        check(large.effective(server: [1, 1, 2], eligible: all).count == 70000, "70k local pins")
        check(large.effective(server: [], eligible: all).first == 70000, "Int ordering")
        large.local = [Int64.max, Int64.min]
        large.order = large.local
        let encoded = try JSONEncoder().encode(large)
        check(String(decoding: encoded, as: UTF8.self).contains("\"9223372036854775807\""), "exact string encoding")
        check(try JSONDecoder().decode(WhitegramLocalPinState.self, from: encoded) == large, "Int64 roundtrip")
        for invalid in [
            #"{"local":[1],"hidden":[],"order":[]}"#,
            #"{"local":["01"],"hidden":[],"order":[]}"#,
            #"{"local":["1","1"],"hidden":[],"order":[]}"#,
            #"{"local":["1"],"hidden":["1"],"order":[]}"#,
            #"{"local":["9223372036854775808"],"hidden":[],"order":[]}"#
        ] { rejects("malformed ids") { _ = try JSONDecoder().decode(WhitegramLocalPinState.self, from: Data(invalid.utf8)) } }

        let suite = "Whitegram.LocalPins.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WhitegramLocalPinStore(defaults: defaults)
        try store.update(accountId: 111, scope: .group(0)) { $0 = state }
        try store.update(accountId: 111, scope: .group(1)) { $0 = large }
        try store.update(accountId: 111, scope: .filter(1)) { $0.local = [4] }
        try store.update(accountId: 222, scope: .group(0)) { $0.local = [3] }
        check(try store.state(accountId: 111, scope: .group(0)) == state, "root scope")
        check(try store.state(accountId: 111, scope: .group(1)) == large, "archive scope")
        check(try store.state(accountId: 111, scope: .filter(1)).local == [4], "filter distinct from group")
        check(try store.state(accountId: 222, scope: .group(0)).local == [3], "account isolation")
        let reopened = WhitegramLocalPinStore(defaults: defaults)
        check(try reopened.state(accountId: 111, scope: .group(1)) == large, "reopen persistence")
        try store.removeScope(accountId: 111, scope: .filter(1))
        check(try store.state(accountId: 111, scope: .filter(1)) == WhitegramLocalPinState(), "filter deletion clears reusable id")
        check(try store.state(accountId: 111, scope: .group(1)) == large, "filter deletion preserves archive")
        for id: Int32 in [2, 3] {
            try store.update(accountId: 111, scope: .filter(id)) { $0.local = [4] }
        }
        try store.removeScopes(accountId: 111, scopes: [.filter(2), .filter(3)])
        check(try store.state(accountId: 111, scope: .filter(2)).local.isEmpty, "batch deletion first filter")
        check(try store.state(accountId: 111, scope: .filter(3)).local.isEmpty, "batch deletion second filter")
        let key = WhitegramLocalPinStore.key(accountId: 111)
        let before = defaults.data(forKey: key)
        rejects("atomic update") { try store.update(accountId: 111, scope: .group(0)) { $0.local = [999]; throw WhitegramLocalPinError.staleOrder } }
        check(defaults.data(forKey: key) == before, "failed update bytes preserved")
        for raw: Any in [Data("broken".utf8), "wrong type", Data(#"{"version":2,"scopes":{}}"#.utf8), Data(#"{"version":1,"scopes":{"f:01":{"local":[],"hidden":[],"order":[]}}}"#.utf8)] {
            defaults.set(raw, forKey: key)
            let before = defaults.object(forKey: key) as! NSObject
            rejects("malformed store") { try store.update(accountId: 111, scope: .group(0)) { $0.local = [5] } }
            rejects("malformed store batch deletion") { try store.removeScopes(accountId: 111, scopes: [.filter(2), .filter(3)]) }
            try store.removeScopes(accountId: 111, scopes: [])
            check((defaults.object(forKey: key) as! NSObject) == before, "malformed store retained")
        }
        store.reset(accountId: 111)
        check(try store.state(accountId: 111, scope: .group(0)) == WhitegramLocalPinState(), "explicit reset")
        check(try store.state(accountId: 222, scope: .group(0)).local == [3], "reset account isolation")
        print("\(checks) local pin policy/storage checks passed")
    }
}
