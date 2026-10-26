import Foundation

public struct WhitegramOnlineHistoryEntry: Codable, Equatable {
    public let id: UUID
    public let peerId: Int64
    public let peerName: String
    public let peerUsername: String?
    public let isOnline: Bool
    public let isContact: Bool
    public let timestamp: Double
    public let serverTimestamp: Double?

    init(peerId: Int64, peerName: String, peerUsername: String?, isOnline: Bool, timestamp: Double, serverTimestamp: Double? = nil, isContact: Bool = true) {
        self.id = UUID()
        self.peerId = peerId
        self.peerName = String(peerName.prefix(256))
        self.peerUsername = peerUsername.map { String($0.prefix(64)) }
        self.isOnline = isOnline
        self.isContact = isContact
        self.timestamp = timestamp
        self.serverTimestamp = serverTimestamp
    }

    var isValid: Bool {
        return peerId > 0 && whitegramHistoryValidPeer(String(peerId)) && ((UInt64(peerId) >> 32) & 7) == 0 && timestamp.isFinite && timestamp >= 0
            && timestamp <= Date.distantFuture.timeIntervalSince1970
            && (serverTimestamp.map { $0.isFinite && $0 >= 0 && $0 <= Date.distantFuture.timeIntervalSince1970 } ?? true)
            && peerName.count <= 256 && (peerUsername?.count ?? 0) <= 64
            && peerName.utf8.count <= 2048 && (peerUsername?.utf8.count ?? 0) <= 256
    }
}

public struct WhitegramOnlineHistoryQuery {
    public var peerId: Int64?
    public var date: DateInterval?
    public var text = ""

    public init() {}

    public func apply(to entries: [WhitegramOnlineHistoryEntry]) -> [WhitegramOnlineHistoryEntry] {
        let text = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.reversed().filter { entry in
            if let peerId, entry.peerId != peerId { return false }
            if let date, entry.timestamp < date.start.timeIntervalSince1970 || entry.timestamp >= date.end.timeIntervalSince1970 { return false }
            return text.isEmpty || entry.peerName.localizedCaseInsensitiveContains(text)
                || (entry.peerUsername?.localizedCaseInsensitiveContains(text) ?? false)
                || String(entry.peerId) == text
        }
    }
}

private struct WhitegramOnlineHistoryArchive: Codable {
    let version: Int
    let accountId: Int64
    let entries: [WhitegramOnlineHistoryEntry]
}

private enum WhitegramOnlineHistoryError: LocalizedError {
    case invalidArchive

    var errorDescription: String? { return "Could not read the online-history archive. Existing data has not been replaced." }
}

public final class WhitegramOnlineHistoryStore: NSObject {
    public static let maximumEntries = 2000
    public static let pageSize = 50
    public static let updatedNotification = Notification.Name("WhitegramOnlineHistoryUpdated")
    private static let maximumBytes = 8 * 1024 * 1024
    private static let registryLock = NSLock()
    private static var stores: [Int64: WhitegramOnlineHistoryStore] = [:]

    public static func forAccount(_ accountId: Int64) -> WhitegramOnlineHistoryStore {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let store = stores[accountId] { return store }
        let store = WhitegramOnlineHistoryStore(accountId: accountId, defaults: .standard)
        stores[accountId] = store
        return store
    }

    private let accountId: Int64
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "Whitegram.OnlineHistory", qos: .utility)
    private var entries: [WhitegramOnlineHistoryEntry]?
    private var loadError: Error?
    var storageKey: String { return "WhitegramOnlineHistory.v1.\(self.accountId)" }

    init(accountId: Int64, defaults: UserDefaults) {
        self.accountId = accountId
        self.defaults = defaults
        super.init()
    }

    private func load() throws -> [WhitegramOnlineHistoryEntry] {
        if let loadError { throw loadError }
        if let entries { return entries }
        do {
            guard let object = defaults.object(forKey: storageKey) else { self.entries = []; return [] }
            guard let data = object as? Data, data.count <= Self.maximumBytes else { throw WhitegramOnlineHistoryError.invalidArchive }
            let archive = try JSONDecoder().decode(WhitegramOnlineHistoryArchive.self, from: data)
            guard archive.version == 1, archive.accountId == accountId, archive.entries.count <= Self.maximumEntries,
                  archive.entries.allSatisfy({ $0.isValid && $0.peerId != accountId }),
                  Set(archive.entries.map { $0.id }).count == archive.entries.count else { throw WhitegramOnlineHistoryError.invalidArchive }
            self.entries = archive.entries
            return archive.entries
        } catch {
            self.loadError = error
            throw error
        }
    }

    private func save(_ entries: [WhitegramOnlineHistoryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(WhitegramOnlineHistoryArchive(version: 1, accountId: accountId, entries: entries))
        guard data.count <= Self.maximumBytes else { throw WhitegramOnlineHistoryError.invalidArchive }
        defaults.set(data, forKey: storageKey)
        self.entries = entries
        self.loadError = nil
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.updatedNotification, object: self) }
    }

    func append(_ incoming: [WhitegramOnlineHistoryEntry]) {
        guard !incoming.isEmpty else { return }
        queue.async {
            do {
                var entries = try self.load()
                var changed = false
                for entry in incoming where entry.isValid && entry.peerId != self.accountId {
                    if entries.last(where: { $0.peerId == entry.peerId })?.isOnline == entry.isOnline { continue }
                    entries.append(entry)
                    changed = true
                    if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
                }
                if changed { try self.save(entries) }
            } catch {
                self.loadError = error
                NSLog("Whitegram: online-history capture failed (%@)", String(describing: type(of: error)))
                DispatchQueue.main.async { NotificationCenter.default.post(name: Self.updatedNotification, object: self) }
            }
        }
    }

    public func snapshot(completion: @escaping (Result<[WhitegramOnlineHistoryEntry], Error>) -> Void) {
        queue.async {
            let result = Result { try self.load() }
            DispatchQueue.main.async { completion(result) }
        }
    }

    public func clear(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { try self.save([]) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Original v2 is shared and has no account field. The caller must explicitly
    /// bind it to this account; the original bytes remain available for recovery.
    public func migrateOriginalForThisAccount(completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async {
            let result = Result { () -> Int in
                guard let object = self.defaults.object(forKey: "wg_onlineHistory_v2") else { return 0 }
                guard let data = object as? Data, data.count <= Self.maximumBytes else { throw WhitegramOnlineHistoryError.invalidArchive }
                let original = try JSONDecoder().decode([WhitegramOnlineHistoryLegacyEntry].self, from: data)
                guard original.count <= Self.maximumEntries,
                      original.allSatisfy({ $0.peerName.count <= 256 && $0.peerName.utf8.count <= 2048 && ($0.peerUsername?.count ?? 0) <= 64 && ($0.peerUsername?.utf8.count ?? 0) <= 256 }) else { throw WhitegramOnlineHistoryError.invalidArchive }
                let incoming = original.map { $0.entry }
                guard incoming.allSatisfy({ $0.isValid && $0.peerId != self.accountId }) else { throw WhitegramOnlineHistoryError.invalidArchive }
                var entries = try self.load()
                let previousIds = Set(entries.map(\.id))
                for entry in incoming {
                    if entries.contains(where: { $0.sameObservation(as: entry) }) { continue }
                    entries.append(entry)
                }
                entries.sort { $0.timestamp < $1.timestamp }
                if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
                let added = entries.filter { !previousIds.contains($0.id) }.count
                if added > 0 { try self.save(entries) }
                return added
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// Beta 3.2 SGOnlineHistoryEntry.decode at 0x21162c; isContact is additive,
// serverTimestamp and peerUsername use decodeIfPresent. No UUID/account envelope.
private struct WhitegramOnlineHistoryLegacyEntry: Decodable {
    let peerId: Int64
    let peerName: String
    let peerUsername: String?
    let isOnline: Bool
    let timestamp: Double
    let serverTimestamp: Double?
    let isContact: Bool?

    var entry: WhitegramOnlineHistoryEntry {
        return WhitegramOnlineHistoryEntry(peerId: peerId, peerName: peerName, peerUsername: peerUsername,
            isOnline: isOnline, timestamp: timestamp, serverTimestamp: serverTimestamp, isContact: isContact ?? false)
    }
}

private extension WhitegramOnlineHistoryEntry {
    func sameObservation(as other: WhitegramOnlineHistoryEntry) -> Bool {
        return peerId == other.peerId && peerName == other.peerName && peerUsername == other.peerUsername
            && isOnline == other.isOnline && isContact == other.isContact
            && timestamp == other.timestamp && serverTimestamp == other.serverTimestamp
    }
}
