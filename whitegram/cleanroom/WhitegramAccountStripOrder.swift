import Foundation

public enum WhitegramAccountStripOrder {
    /// A drag is valid only for the exact live membership snapshot it began with.
    public static func moving(_ id: Int64, before target: Int64, snapshot: [Int64], live: [Int64]) -> [Int64]? {
        guard Set(snapshot).count == snapshot.count, Set(live).count == live.count,
              Set(snapshot) == Set(live), id != target, snapshot.contains(id), snapshot.contains(target) else { return nil }
        var result = snapshot.filter { $0 != id }
        guard let index = result.firstIndex(of: target) else { return nil }
        result.insert(id, at: index)
        return result
    }
}
