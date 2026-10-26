import Foundation
import Postbox

@main
enum WhitegramLocalPremiumTests {
    static func main() {
        let defaults = UserDefaults.standard
        for key in [WhitegramPreferences.storageKey, "WhitegramPrivacySettings.v1", "wg_localPremium"] { defaults.removeObject(forKey: key) }
        defer {
            for key in [WhitegramPreferences.storageKey, "WhitegramPrivacySettings.v1", "wg_localPremium"] { defaults.removeObject(forKey: key) }
        }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label)
            checks += 1
        }
        let identity = PeerId(100)
        let actual = TelegramUser(id: identity, nameColor: .preset(PeerNameColor(rawValue: 3)), emojiStatus: PeerEmojiStatus(content: .emoji(fileId: 55), expirationDate: 90))
        let other = TelegramUser(id: PeerId(200))
        func projected(_ account: Int64) -> TelegramUser {
            guard case let .user(value) = WhitegramLocalPremiumPresentation.peer(.user(actual), accountId: account, accountPeerId: identity) else { fatalError("missing user") }
            return value
        }
        let policy = WhitegramLocalPremiumPolicy(nameColor: 6, nameBackgroundEmoji: 101, profileColor: 2, profileBackgroundEmoji: 102, emojiStatus: Int64.max)
        check(WhitegramLocalPremiumPresentation.save(policy, accountId: 1), "save A")
        check(WhitegramLocalPremiumPresentation.save(WhitegramLocalPremiumPolicy(profileColor: 4), accountId: 2), "save B")
        check(projected(1) === actual, "disabled returns server object identity")
        check(WhitegramPreferences.set(true, for: "localPremium"), "enable")
        let shown = projected(1)
        check(shown !== actual && shown.flags.contains(.isPremium), "detached premium badge")
        check(shown.emojiStatus?.content == .emoji(fileId: Int64.max) && shown.nameColor == .preset(PeerNameColor(rawValue: 6)), "exact local values consumed")
        check(actual.flags.isEmpty && actual.emojiStatus?.content == .emoji(fileId: 55), "server state unchanged")
        check(projected(2).profileColor?.rawValue == 4 && projected(2).nameColor == actual.nameColor, "account isolation and absent-value fallback")
        if case let .user(value) = WhitegramLocalPremiumPresentation.peer(.user(other), accountId: 1, accountPeerId: identity) {
            check(value === other, "other user never decorated")
        } else { fatalError("wrong peer") }
        if case .channel = WhitegramLocalPremiumPresentation.peer(.channel, accountId: 1, accountPeerId: identity) { checks += 1 }
        else { fatalError("channel decorated") }
        check(WhitegramLocalPremiumPresentation.peer(nil, accountId: 1, accountPeerId: identity) == nil, "nil peer")
        check(!WhitegramLocalPremiumPresentation.save(WhitegramLocalPremiumPolicy(emojiStatus: 0), accountId: 1), "invalid save rejected")
        check(WhitegramLocalPremiumPresentation.current(accountId: 1) == policy, "invalid save preserved data")
        check(WhitegramPreferences.set(false, for: "localPremium"), "disable")
        check(projected(1) === actual, "disable restores actual object")
        check(WhitegramPreferences.set(true, for: "localPremium"), "re-enable")
        check(projected(1).emojiStatus == shown.emojiStatus, "settings survive disable")
        check(WhitegramLocalPremiumPresentation.save(WhitegramLocalPremiumPolicy(), accountId: 1), "reset")
        check(projected(1).nameColor == actual.nameColor && projected(1).emojiStatus == actual.emojiStatus, "reset falls back to real profile")
        check(WhitegramLocalPremiumPresentation.current(accountId: 2).profileColor == 4, "reset does not touch other account")
        check(WhitegramPreferences.set("invalid", for: WhitegramLocalPremiumPresentation.accountValuesKey), "corrupt nested store")
        let before = defaults.data(forKey: WhitegramPreferences.storageKey)
        check(!WhitegramLocalPremiumPresentation.save(policy, accountId: 1), "malformed store fails closed")
        check(before == defaults.data(forKey: WhitegramPreferences.storageKey), "malformed bytes preserved")
        print("Whitegram local Premium: \(checks) storage/presentation checks passed (API fixtures)")
    }
}
