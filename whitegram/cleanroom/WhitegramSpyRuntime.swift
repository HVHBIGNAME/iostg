import Foundation
import Postbox
import TelegramApi

public enum WhitegramSpyRuntime {
    private static let captureQueue = DispatchQueue(label: "Whitegram.Spy.Capture", qos: .utility)
    private static func enabled(_ key: String) -> Bool {
        return WhitegramPreferences.bool(key, default: UserDefaults.standard.bool(forKey: "wg_" + key))
    }

    static func recordUsers(transaction: Transaction, accountPeerId: PeerId, users: [PeerId: Api.User], acceptedPeerIds: Set<PeerId>) {
        var statuses: [PeerId: Api.UserStatus] = [:]
        for id in acceptedPeerIds {
            if let user = users[id], case let .user(data) = user, let status = data.status { statuses[id] = status }
        }
        recordPresences(transaction: transaction, accountPeerId: accountPeerId, statuses: statuses, acceptedPeerIds: acceptedPeerIds)
    }

    static func recordPresences(transaction: Transaction, accountPeerId: PeerId, statuses: [PeerId: Api.UserStatus], acceptedPeerIds: Set<PeerId>) {
        guard enabled("trackLastOnline") else { return }
        let now = Int32(clamping: Int64(Date().timeIntervalSince1970))
        let store = WhitegramSpyStore.forAccount(accountPeerId.toInt64())
        for id in acceptedPeerIds {
            guard id != accountPeerId, id.namespace == Namespaces.Peer.CloudUser,
                  transaction.isPeerContact(peerId: id),
                  let user = transaction.getPeer(id) as? TelegramUser, user.botInfo == nil, let status = statuses[id] else { continue }
            let timestamp: Int32
            switch status {
            case .userStatusOnline: timestamp = now
            case let .userStatusOffline(data): timestamp = data.wasOnline
            default: continue
            }
            guard timestamp > 0, timestamp <= now else { continue }
            let rawPeerId = id.toInt64()
            captureQueue.async {
                do { try store.record(peerId: rawPeerId, lastOnline: timestamp) }
                catch { NSLog("Whitegram: last-online store unavailable") }
            }
        }
    }

    public static func displayPresence(_ presence: TelegramUserPresence, accountPeerId: PeerId, peerId: PeerId, now: Int32) -> TelegramUserPresence {
        guard enabled("trackLastOnline"), peerId != accountPeerId, peerId.namespace == Namespaces.Peer.CloudUser else { return presence }
        // Explicit native timestamps always win; only privacy-coarse values use
        // previously received evidence. Typing/expiry never update the store.
        switch presence.status {
        case .present: return presence
        case .recently where Int64(presence.lastActivity) + 30 >= Int64(now): return presence
        default: break
        }
        do {
            guard let timestamp = try WhitegramSpyStore.forAccount(accountPeerId.toInt64()).lastOnline(peerId: peerId.toInt64()), timestamp < now else { return presence }
            return TelegramUserPresence(status: .present(until: timestamp), lastActivity: presence.lastActivity)
        } catch {
            NSLog("Whitegram: last-online display unavailable")
            return presence
        }
    }

    public static func recordReadDate(accountPeerId: PeerId, id: MessageId, timestamp: Int32) {
        guard enabled("saveReadDates"), id.namespace == Namespaces.Message.Cloud,
              id.peerId.namespace == Namespaces.Peer.CloudUser, id.peerId != accountPeerId,
              timestamp > 0, timestamp <= Int32(clamping: Int64(Date().timeIntervalSince1970)) else { return }
        captureQueue.async {
            do { try WhitegramSpyStore.forAccount(accountPeerId.toInt64()).record(peerId: id.peerId.toInt64(), messageId: id.id, readDate: timestamp) }
            catch { NSLog("Whitegram: read-date store unavailable") }
        }
    }

    public static func savedReadDate(accountPeerId: PeerId, id: MessageId) -> Int32? {
        guard enabled("saveReadDates"), id.namespace == Namespaces.Message.Cloud, id.peerId != accountPeerId else { return nil }
        do { return try WhitegramSpyStore.forAccount(accountPeerId.toInt64()).readDate(peerId: id.peerId.toInt64(), messageId: id.id) }
        catch { NSLog("Whitegram: read-date lookup unavailable"); return nil }
    }
}
