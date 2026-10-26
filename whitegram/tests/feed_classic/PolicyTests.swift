import Foundation

@main
enum PolicyTests {
    static func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label) }
    static func key(_ peer: Int64, _ id: Int32, _ timestamp: Int32) -> WhitegramFeedKey {
        return WhitegramFeedKey(peer: peer, id: id, timestamp: timestamp)
    }

    static func main() throws {
        var merge = WhitegramFeedMerge(peers: [1, 2])
        check(merge.next() == .fetch([1, 2]), "All heads must be known")
        try merge.accept(peer: 1, keys: [key(1, 10, 100), key(1, 9, 90)], nextOffset: 9, exhausted: false)
        check(merge.next() == .fetch([2]), "Do not emit before the other channel")
        try merge.accept(peer: 2, keys: [key(2, 20, 95), key(2, 19, 85)], nextOffset: 19, exhausted: false)
        check(merge.next() == .post(key(1, 10, 100)), "Newest globally")
        check(merge.next() == .post(key(2, 20, 95)), "Interleave channels")
        check(merge.next() == .post(key(1, 9, 90)), "Consume first channel page")
        check(merge.next() == .fetch([1]), "Refill barrier before emitting 85")
        try merge.accept(peer: 1, keys: [key(1, 9, 90), key(1, 8, 89)], nextOffset: 8, exhausted: false)
        check(merge.next() == .post(key(1, 8, 89)), "Page-overlap dedupe")
        check(merge.next() == .fetch([1]), "Do not guess EOS")
        do { try merge.accept(peer: 1, keys: [], nextOffset: 8, exhausted: false); preconditionFailure("Non-advancing page accepted") }
        catch { }
        check(merge.offset(peer: 1) == 8, "Rejected page preserves retry cursor")
        try merge.accept(peer: 1, keys: [], nextOffset: 6, exhausted: false)
        check(merge.next() == .fetch([1]), "All-service/deleted page advances without ending history")
        try merge.accept(peer: 1, keys: [], nextOffset: nil, exhausted: true)
        check(merge.next() == .post(key(2, 19, 85)), "Release blocked channel after real EOF")
        try merge.accept(peer: 2, keys: [], nextOffset: nil, exhausted: true)
        check(merge.next() == .end, "Every stream exhausted")
        var empty = WhitegramFeedMerge(peers: [])
        check(empty.next() == .end, "No subscriptions")

        // Deterministic model comparison: different page lengths, ties, multiple channels.
        for seed in 1...30 {
            let peers = (1...7).map(Int64.init)
            var histories: [Int64: [WhitegramFeedKey]] = [:]
            for peer in peers {
                histories[peer] = (1...35).map { id in key(peer, Int32(id), Int32((id * 9 + Int(peer) * seed) / 3)) }.sorted(by: >)
            }
            let expected = histories.values.flatMap { $0 }.sorted(by: >)
            var actual: [WhitegramFeedKey] = []
            var pager = WhitegramFeedMerge(peers: peers)
            var turns = 0
            loop: while true {
                turns += 1
                precondition(turns < 2000, "Pagination did not terminate")
                switch pager.next() {
                case let .fetch(missing):
                    for peer in missing {
                        let count = (Int(peer) + seed) % 9 + 1
                        let page = Array(histories[peer]!.prefix(count))
                        histories[peer]!.removeFirst(page.count)
                        try pager.accept(peer: peer, keys: page, nextOffset: page.last?.id, exhausted: page.isEmpty)
                    }
                case let .post(post): actual.append(post)
                case .end: break loop
                }
            }
            check(actual == expected, "K-way pagination equals a full chronological sort")
        }
        WhitegramClassicStyle.setEnabled(false)
        check(WhitegramClassicStyle.navigationHeight(original: 60) == 60, "Modern off restores layout")
        WhitegramClassicStyle.setEnabled(true)
        check(WhitegramClassicStyle.navigationHeight(original: 60) == 44, "Classic navigation geometry")
        check(WhitegramClassicStyle.navigationHeight(original: 32) == 32, "Do not enlarge an already compact header")
        check(WhitegramClassicStyle.tabHeight(landscape: false, safeBottom: 34) == 83, "Portrait safe area")
        check(WhitegramClassicStyle.tabHeight(landscape: true, safeBottom: 21) == 55, "Landscape safe area")
        WhitegramClassicStyle.setEnabled(false)
        check(!WhitegramClassicStyle.enabled, "Classic mode reverses")
        print("Feed merge: 30 paginated model comparisons (7,350 posts), boundary/error/dedup tests; classic on/off/geometry passed")
    }
}
