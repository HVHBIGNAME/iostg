import Foundation
import Postbox

public enum WhitegramLocalPremiumPresentation {
    public static let accountValuesKey = "clientInterfaceLocalPremiumAccounts"

    public static func current(accountId: Int64) -> WhitegramLocalPremiumPolicy {
        let accounts = WhitegramPreferences.values()[accountValuesKey] as? [String: Any]
        return WhitegramLocalPremiumPolicy.decode(accounts?[String(accountId)]) ?? WhitegramLocalPremiumPolicy()
    }

    @discardableResult
    public static func save(_ policy: WhitegramLocalPremiumPolicy, accountId: Int64) -> Bool {
        guard policy.isValid else { return false }
        do {
            return try WhitegramPreferences.updateForTransfer { _, values in
                if let stored = values[accountValuesKey], !(stored is [String: Any]) {
                    throw NSError(domain: "WhitegramLocalPremium", code: 1)
                }
                var accounts = (values[accountValuesKey] as? [String: Any]) ?? [:]
                accounts[String(accountId)] = policy.values
                return (result: true, changes: [accountValuesKey: accounts], mirrors: [:], notifications: [])
            }
        } catch {
            NSLog("Whitegram: local presentation could not be saved (%@)", String(describing: error))
            return false
        }
    }

    public static func peer(_ peer: EnginePeer?, accountId: Int64, accountPeerId: PeerId) -> EnginePeer? {
        guard WhitegramPreferences.bool("localPremium"), case let .user(user) = peer, user.id == accountPeerId else { return peer }
        let policy = current(accountId: accountId)
        // This detached value is used only by the profile renderer. It is never persisted to Postbox.
        var result = user.withUpdatedFlags(user.flags.union(.isPremium))
        if let color = policy.nameColor { result = result.withUpdatedNameColor(.preset(PeerNameColor(rawValue: color))) }
        if let emoji = policy.nameBackgroundEmoji { result = result.withUpdatedBackgroundEmojiId(emoji) }
        if let color = policy.profileColor { result = result.withUpdatedProfileColor(PeerNameColor(rawValue: color)) }
        if let emoji = policy.profileBackgroundEmoji { result = result.withUpdatedProfileBackgroundEmojiId(emoji) }
        if let emoji = policy.emojiStatus { result = result.withUpdatedEmojiStatus(PeerEmojiStatus(content: .emoji(fileId: emoji), expirationDate: nil)) }
        return .user(result)
    }
}
