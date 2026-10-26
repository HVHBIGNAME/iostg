import Postbox

struct UserInfoFlags: OptionSet {
    let rawValue: Int
    static let isPremium = UserInfoFlags(rawValue: 16)
}

struct PeerNameColor: Equatable {
    let rawValue: Int32
}

enum PeerColor: Equatable { case preset(PeerNameColor) }
struct PeerEmojiStatus: Equatable {
    enum Content: Equatable { case emoji(fileId: Int64) }
    let content: Content
    let expirationDate: Int32?
}

public final class TelegramUser {
    let id: PeerId
    let flags: UserInfoFlags
    let nameColor: PeerColor?
    let backgroundEmojiId: Int64?
    let profileColor: PeerNameColor?
    let profileBackgroundEmojiId: Int64?
    let emojiStatus: PeerEmojiStatus?

    init(id: PeerId, flags: UserInfoFlags = [], nameColor: PeerColor? = nil, backgroundEmojiId: Int64? = nil,
         profileColor: PeerNameColor? = nil, profileBackgroundEmojiId: Int64? = nil, emojiStatus: PeerEmojiStatus? = nil) {
        self.id = id
        self.flags = flags
        self.nameColor = nameColor
        self.backgroundEmojiId = backgroundEmojiId
        self.profileColor = profileColor
        self.profileBackgroundEmojiId = profileBackgroundEmojiId
        self.emojiStatus = emojiStatus
    }

    func withUpdatedFlags(_ value: UserInfoFlags) -> TelegramUser {
        return TelegramUser(id: id, flags: value, nameColor: nameColor, backgroundEmojiId: backgroundEmojiId, profileColor: profileColor, profileBackgroundEmojiId: profileBackgroundEmojiId, emojiStatus: emojiStatus)
    }
    func withUpdatedNameColor(_ value: PeerColor) -> TelegramUser {
        return TelegramUser(id: id, flags: flags, nameColor: value, backgroundEmojiId: backgroundEmojiId, profileColor: profileColor, profileBackgroundEmojiId: profileBackgroundEmojiId, emojiStatus: emojiStatus)
    }
    func withUpdatedBackgroundEmojiId(_ value: Int64) -> TelegramUser {
        return TelegramUser(id: id, flags: flags, nameColor: nameColor, backgroundEmojiId: value, profileColor: profileColor, profileBackgroundEmojiId: profileBackgroundEmojiId, emojiStatus: emojiStatus)
    }
    func withUpdatedProfileColor(_ value: PeerNameColor) -> TelegramUser {
        return TelegramUser(id: id, flags: flags, nameColor: nameColor, backgroundEmojiId: backgroundEmojiId, profileColor: value, profileBackgroundEmojiId: profileBackgroundEmojiId, emojiStatus: emojiStatus)
    }
    func withUpdatedProfileBackgroundEmojiId(_ value: Int64) -> TelegramUser {
        return TelegramUser(id: id, flags: flags, nameColor: nameColor, backgroundEmojiId: backgroundEmojiId, profileColor: profileColor, profileBackgroundEmojiId: value, emojiStatus: emojiStatus)
    }
    func withUpdatedEmojiStatus(_ value: PeerEmojiStatus) -> TelegramUser {
        return TelegramUser(id: id, flags: flags, nameColor: nameColor, backgroundEmojiId: backgroundEmojiId, profileColor: profileColor, profileBackgroundEmojiId: profileBackgroundEmojiId, emojiStatus: value)
    }
}

public enum EnginePeer {
    case user(TelegramUser)
    case channel
}
