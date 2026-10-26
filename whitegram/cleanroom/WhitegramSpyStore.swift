import Foundation

public struct WhitegramSpyPeer: Codable, Equatable {
    public var lastOnline: Int32?
    public var readDates: [String: Int32] = [:]

    public init() {}
}

private struct WhitegramSpyArchive: Codable {
    let version: Int
    let accountId: Int64
    var peers: [String: WhitegramSpyPeer]
}

private enum WhitegramSpyError: Error {
    case invalidArchive
}

/// Observed timestamps only. A read date is bound to one complete cloud message
/// identity, never inferred for every message below an outbox read watermark.
public final class WhitegramSpyStore {
    public static let maximumPeers = 2000
    public static let maximumReadDates = 2000
    private static let registryLock = NSLock()
    private static var stores: [Int64: WhitegramSpyStore] = [:]
    private let accountId: Int64
    private let defaults: UserDefaults
    private let lock = NSLock()
    var storageKey: String { return "WhitegramSpy.v1.\(accountId)" }

    public static func forAccount(_ accountId: Int64) -> WhitegramSpyStore {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let store = stores[accountId] { return store }
        let store = WhitegramSpyStore(accountId: accountId, defaults: .standard)
        stores[accountId] = store
        return store
    }

    init(accountId: Int64, defaults: UserDefaults) {
        self.accountId = accountId
        self.defaults = defaults
    }

    private func validPeer(_ peerId: Int64) -> Bool {
        return peerId != accountId && whitegramHistoryValidPeer(String(peerId)) && ((UInt64(peerId) >> 32) & 7) == 0
    }

    private func load() throws -> WhitegramSpyArchive {
        guard let object = defaults.object(forKey: storageKey) else { return WhitegramSpyArchive(version: 1, accountId: accountId, peers: [:]) }
        guard let data = object as? Data, data.count <= 2 * 1024 * 1024 else { throw WhitegramSpyError.invalidArchive }
        let archive = try JSONDecoder().decode(WhitegramSpyArchive.self, from: data)
        guard archive.version == 1, archive.accountId == accountId, archive.peers.count <= Self.maximumPeers,
              archive.peers.values.reduce(0, { $0 + $1.readDates.count }) <= Self.maximumReadDates else { throw WhitegramSpyError.invalidArchive }
        for (key, peer) in archive.peers {
            guard let raw = Int64(key), String(raw) == key, validPeer(raw),
                  peer.lastOnline.map({ $0 > 0 }) ?? true,
                  peer.readDates.allSatisfy({ key, value in Int32(key).map { $0 > 0 && String($0) == key } == true && value > 0 }) else { throw WhitegramSpyError.invalidArchive }
        }
        return archive
    }

    public func snapshot() throws -> [String: WhitegramSpyPeer] {
        lock.lock()
        defer { lock.unlock() }
        return try load().peers
    }

    public func record(peerId: Int64, lastOnline: Int32? = nil, messageId: Int32? = nil, readDate: Int32? = nil) throws {
        guard validPeer(peerId), lastOnline.map({ $0 > 0 }) ?? true,
              (messageId == nil) == (readDate == nil), messageId.map({ $0 > 0 }) ?? true,
              readDate.map({ $0 > 0 }) ?? true, lastOnline != nil || readDate != nil else { return }
        lock.lock()
        defer { lock.unlock() }
        var archive = try load()
        let key = String(peerId)
        var peer = archive.peers[key] ?? WhitegramSpyPeer()
        if let lastOnline { peer.lastOnline = max(peer.lastOnline ?? 0, lastOnline) }
        if let messageId, let readDate, peer.readDates[String(messageId)] == nil {
            peer.readDates[String(messageId)] = readDate
        }
        if archive.peers[key] == peer { return }
        archive.peers[key] = peer
        // Stable eviction by oldest evidence time, with exact identity tie breaks.
        let dates = archive.peers.flatMap { peerKey, peer in peer.readDates.map { (peerKey, $0.key, $0.value) } }
            .sorted { $0.2 != $1.2 ? $0.2 < $1.2 : ($0.0, $0.1) < ($1.0, $1.1) }
        for date in dates.prefix(max(0, dates.count - Self.maximumReadDates)) {
            archive.peers[date.0]?.readDates.removeValue(forKey: date.1)
        }
        let oldest = archive.peers.sorted { lhs, rhs in
            let left = max(lhs.value.lastOnline ?? 0, lhs.value.readDates.values.max() ?? 0)
            let right = max(rhs.value.lastOnline ?? 0, rhs.value.readDates.values.max() ?? 0)
            return left != right ? left < right : lhs.key < rhs.key
        }
        for item in oldest.prefix(max(0, archive.peers.count - Self.maximumPeers)) { archive.peers.removeValue(forKey: item.key) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= 2 * 1024 * 1024 else { throw WhitegramSpyError.invalidArchive }
        defaults.set(data, forKey: storageKey)
    }

    public func lastOnline(peerId: Int64) throws -> Int32? { return try snapshot()[String(peerId)]?.lastOnline }
    public func readDate(peerId: Int64, messageId: Int32) throws -> Int32? { return try snapshot()[String(peerId)]?.readDates[String(messageId)] }
}
