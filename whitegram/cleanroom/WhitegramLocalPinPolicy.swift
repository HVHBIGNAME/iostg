import Foundation

/// All identifiers are encoded as decimal strings, including full packed PeerIds.
public struct WhitegramLocalPinState: Codable, Equatable {
    public var local: [Int64] = []
    public var hidden: [Int64] = []
    public var order: [Int64] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case local, hidden, order }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func ids(_ key: CodingKeys) throws -> [Int64] {
            let strings = try values.decode([String].self, forKey: key)
            let result = strings.compactMap(Int64.init)
            guard result.count == strings.count, result.map(String.init) == strings,
                  Set(result).count == result.count else { throw WhitegramLocalPinError.invalidStore }
            return result
        }
        self.local = try ids(.local)
        self.hidden = try ids(.hidden)
        self.order = try ids(.order)
        guard Set(local).isDisjoint(with: hidden) else { throw WhitegramLocalPinError.invalidStore }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(local.map(String.init), forKey: .local)
        try values.encode(hidden.map(String.init), forKey: .hidden)
        try values.encode(order.map(String.init), forKey: .order)
    }

    public func effective(server: [Int64], eligible: Set<Int64>) -> [Int64] {
        let members = Set(local + server).intersection(eligible).subtracting(hidden)
        var seen = Set<Int64>()
        return (order + local + server).filter { members.contains($0) && seen.insert($0).inserted }
    }

    public mutating func toggle(_ id: Int64, server: [Int64], eligible: Set<Int64>) throws {
        guard eligible.contains(id) else { throw WhitegramLocalPinError.unavailablePeer }
        let current = effective(server: server, eligible: eligible)
        if current.contains(id) {
            local.removeAll { $0 == id }
            // A server pin can be hidden locally without modifying cloud state.
            if server.contains(id) && !hidden.contains(id) { hidden.append(id) }
            order.removeAll { $0 == id }
        } else {
            hidden.removeAll { $0 == id }
            if !server.contains(id) && !local.contains(id) { local.append(id) }
            order.removeAll { $0 == id }
            order.insert(id, at: 0)
        }
    }

    public mutating func reorder(_ requested: [Int64], expected: [Int64], server: [Int64], eligible: Set<Int64>) throws {
        let current = effective(server: server, eligible: eligible)
        guard current == expected, requested.count == current.count,
              Set(requested).count == requested.count, Set(requested) == Set(current) else {
            throw WhitegramLocalPinError.staleOrder
        }
        // Retain unavailable IDs for an archive/restore or temporary missing peer.
        let visible = Set(requested)
        order = requested + order.filter { !visible.contains($0) }
    }
}

public enum WhitegramLocalPinError: Error {
    case invalidStore, unavailablePeer, staleOrder, disabled
}

public enum WhitegramLocalPinScope: Hashable {
    case group(Int32)
    case filter(Int32)

    public var key: String {
        switch self {
        case let .group(id): return "g:" + String(id)
        case let .filter(id): return "f:" + String(id)
        }
    }

    static func valid(_ key: String) -> Bool {
        guard key.hasPrefix("g:") || key.hasPrefix("f:"), let id = Int32(key.dropFirst(2)) else { return false }
        return String(id) == key.dropFirst(2)
    }
}

/// One file-backed defaults value per AccountRecordId; never copied with preference profiles.
public final class WhitegramLocalPinStore {
    public static let updatedNotification = Notification.Name("WhitegramLocalPinsUpdated.v1")
    public static let shared = WhitegramLocalPinStore(defaults: .standard)
    private static let lock = NSRecursiveLock()
    private let defaults: UserDefaults

    private struct Document: Codable {
        var version = 1
        var scopes: [String: WhitegramLocalPinState] = [:]
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public static func key(accountId: Int64) -> String { "WhitegramLocalPins.v1." + String(accountId) }

    private func read(accountId: Int64) throws -> Document {
        guard accountId != 0 else { throw WhitegramLocalPinError.invalidStore }
        guard let raw = defaults.object(forKey: Self.key(accountId: accountId)) else { return Document() }
        guard let data = raw as? Data else { throw WhitegramLocalPinError.invalidStore }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1, document.scopes.keys.allSatisfy(WhitegramLocalPinScope.valid) else {
            throw WhitegramLocalPinError.invalidStore
        }
        return document
    }

    public func state(accountId: Int64, scope: WhitegramLocalPinScope) throws -> WhitegramLocalPinState {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try read(accountId: accountId).scopes[scope.key] ?? WhitegramLocalPinState()
    }

    public func update(accountId: Int64, scope: WhitegramLocalPinScope, _ change: (inout WhitegramLocalPinState) throws -> Void) throws {
        Self.lock.lock()
        do {
            var document = try read(accountId: accountId)
            var state = document.scopes[scope.key] ?? WhitegramLocalPinState()
            try change(&state)
            document.scopes[scope.key] = state
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
            // Validate writes with the same decoder as reads.
            _ = try JSONDecoder().decode(Document.self, from: data)
            defaults.set(data, forKey: Self.key(accountId: accountId))
        } catch {
            Self.lock.unlock()
            throw error
        }
        Self.lock.unlock()
        NotificationCenter.default.post(name: Self.updatedNotification, object: accountId)
    }

    /// Explicit account deletion/reset only. Disabling the feature retains the order.
    public func reset(accountId: Int64) {
        Self.lock.lock()
        defaults.removeObject(forKey: Self.key(accountId: accountId))
        Self.lock.unlock()
        NotificationCenter.default.post(name: Self.updatedNotification, object: accountId)
    }

    /// Call after confirmed filter deletion, before that numeric filter ID can be reused.
    public func removeScope(accountId: Int64, scope: WhitegramLocalPinScope) throws {
        try removeScopes(accountId: accountId, scopes: [scope])
    }

    /// Multiple deleted filters are removed in one write; failures preserve all scopes.
    public func removeScopes(accountId: Int64, scopes: [WhitegramLocalPinScope]) throws {
        guard !scopes.isEmpty else { return }
        Self.lock.lock()
        do {
            var document = try read(accountId: accountId)
            for scope in scopes { document.scopes.removeValue(forKey: scope.key) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            defaults.set(try encoder.encode(document), forKey: Self.key(accountId: accountId))
        } catch {
            Self.lock.unlock()
            throw error
        }
        Self.lock.unlock()
        NotificationCenter.default.post(name: Self.updatedNotification, object: accountId)
    }
}
