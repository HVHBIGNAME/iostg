import Foundation

/// The nine Codable fields recovered from SGBackedUpMessage (image 46, 0xece620).
/// Original files have no account field. Import requires explicit account binding.
struct WhitegramHistoryLegacyMessage: Codable {
    let peerIdNamespace: Int32
    let peerIdId: Int64
    let messageIdNamespace: Int32
    let messageIdId: Int32
    let authorIdNamespace: Int32?
    let authorIdId: Int64?
    let text: String
    let timestamp: Int32
    let isOutgoing: Bool

    func entry(accountId: String, capturedAt: Double) throws -> WhitegramHistoryEntry {
        guard let peerId = whitegramHistoryPackedPeer(namespace: self.peerIdNamespace, id: self.peerIdId),
              self.messageIdNamespace == 0, self.messageIdId > 0, self.timestamp >= 0,
              self.text.utf8.count <= WhitegramHistoryStore.maximumTextBytes,
              (self.authorIdNamespace == nil) == (self.authorIdId == nil) else {
            throw WhitegramHistoryBackupError.invalidLegacyBackup
        }
        var authorId: String?
        if let namespace = self.authorIdNamespace, let id = self.authorIdId {
            guard let packed = whitegramHistoryPackedPeer(namespace: namespace, id: id) else { throw WhitegramHistoryBackupError.invalidLegacyBackup }
            authorId = String(packed)
        }
        return WhitegramHistoryEntry(accountId: accountId, peerId: String(peerId), namespace: self.messageIdNamespace,
            messageId: self.messageIdId, revision: 0, messageDate: self.timestamp, capturedAt: capturedAt, event: .deleted,
            text: self.text, authorId: authorId, outgoing: self.isOutgoing, mediaCount: 0)
    }
}

extension WhitegramHistoryLegacyMessage {
    init(_ entry: WhitegramHistoryEntry) throws {
        guard entry.textTruncated != true, let peer = whitegramHistoryUnpackedPeer(entry.peerId),
              entry.namespace == 0, entry.messageId > 0 else { throw WhitegramHistoryBackupError.invalidLegacyBackup }
        let author: (namespace: Int32, id: Int64)?
        if let authorId = entry.authorId {
            guard let unpacked = whitegramHistoryUnpackedPeer(authorId) else { throw WhitegramHistoryBackupError.invalidLegacyBackup }
            author = unpacked
        } else { author = nil }
        self.init(peerIdNamespace: peer.namespace, peerIdId: peer.id, messageIdNamespace: entry.namespace,
            messageIdId: entry.messageId, authorIdNamespace: author?.namespace, authorIdId: author?.id,
            text: entry.text, timestamp: entry.messageDate, isOutgoing: entry.outgoing)
    }
}

func whitegramHistoryUnpackedPeer(_ value: String) -> (namespace: Int32, id: Int64)? {
    guard whitegramHistoryValidPeer(value), let raw = Int64(value) else { return nil }
    let bits = UInt64(raw)
    return (Int32((bits >> 32) & 7), Int64(((bits >> 35) << 32) | (bits & 0xffffffff)))
}

enum WhitegramHistoryBackupError: LocalizedError {
    case invalidLegacyBackup

    var errorDescription: String? { return "Invalid, unsupported or oversized original Whitegram backup." }
}

func whitegramHistoryPackedPeer(namespace: Int32, id: Int64) -> Int64? {
    guard (0...2).contains(namespace), id > 0, id <= 0x00ffffffffffffff else { return nil }
    let bits = UInt64(id)
    return Int64(((bits >> 32) << 35) | (UInt64(namespace) << 32) | (bits & 0xffffffff))
}

func whitegramHistoryValidPeer(_ value: String) -> Bool {
    guard let raw = Int64(value), String(raw) == value, raw > 0 else { return false }
    let bits = UInt64(raw)
    let namespace = Int32((bits >> 32) & 7)
    let id = Int64(((bits >> 35) << 32) | (bits & 0xffffffff))
    return whitegramHistoryPackedPeer(namespace: namespace, id: id) == raw
}

public func whitegramHistoryRestorationEntries(_ entries: [WhitegramHistoryEntry], scope: WhitegramHistoryScope) -> [WhitegramHistoryEntry] {
    var seen = Set<WhitegramHistoryMessageId>()
    return WhitegramHistoryQuery(scope: scope, order: .captureTime).apply(to: entries).sorted {
            // Revision is authoritative within a message. Import time must not
            // make an old revision-zero original backup displace a newer capture.
            if $0.messageIdentity == $1.messageIdentity, $0.revision != $1.revision { return $0.revision > $1.revision }
            if $0.messageIdentity != $1.messageIdentity { return $0.key < $1.key }
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt > $1.capturedAt }
            return $0.key < $1.key
        }
        .filter { $0.event != .edited && seen.insert($0.messageIdentity).inserted }
        .sorted {
            if $0.messageDate != $1.messageDate { return $0.messageDate < $1.messageDate }
            if $0.peerId != $1.peerId { return $0.peerId < $1.peerId }
            return $0.messageId < $1.messageId
        }
}
