import Foundation
import Postbox

public func whitegramRemainingBadgeUserId(_ peer: Peer?) -> Int64? {
    guard let user = peer as? TelegramUser, user.id.namespace == Namespaces.Peer.CloudUser,
          user.id.id._internalGetInt64Value() > 0 else { return nil }
    return user.id.id._internalGetInt64Value()
}
