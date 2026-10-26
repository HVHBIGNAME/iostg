import Foundation
import CoreFoundation

public struct WhitegramLocalPremiumPolicy: Codable, Equatable {
    public var nameColor: Int32?
    public var nameBackgroundEmoji: Int64?
    public var profileColor: Int32?
    public var profileBackgroundEmoji: Int64?
    public var emojiStatus: Int64?

    public init(nameColor: Int32? = nil, nameBackgroundEmoji: Int64? = nil, profileColor: Int32? = nil,
                profileBackgroundEmoji: Int64? = nil, emojiStatus: Int64? = nil) {
        self.nameColor = nameColor
        self.nameBackgroundEmoji = nameBackgroundEmoji
        self.profileColor = profileColor
        self.profileBackgroundEmoji = profileBackgroundEmoji
        self.emojiStatus = emojiStatus
    }

    public static func parseInteger(_ text: String, maximum: Int64) -> Int64? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let value = Int64(text), value <= maximum else { return nil }
        return value
    }

    public var isValid: Bool {
        return (nameColor.map { $0 >= 0 } ?? true) && (profileColor.map { $0 >= 0 } ?? true)
            && (nameBackgroundEmoji.map { $0 > 0 } ?? true) && (profileBackgroundEmoji.map { $0 > 0 } ?? true)
            && (emojiStatus.map { $0 > 0 } ?? true)
    }

    public static func decode(_ value: Any?) -> WhitegramLocalPremiumPolicy? {
        guard let values = value as? [String: Any] else { return nil }
        let keys = ["nameColor", "nameBackgroundEmoji", "profileColor", "profileBackgroundEmoji", "emojiStatus"]
        var integers: [String: Int64] = [:]
        for key in keys {
            guard let value = values[key] else { continue }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let integer = Int64(number.stringValue), integer >= 0 else { return nil }
            integers[key] = integer
        }
        for key in ["nameColor", "profileColor"] where integers[key].map({ $0 > Int64(Int32.max) }) == true { return nil }
        let result = Self(nameColor: integers["nameColor"].map(Int32.init), nameBackgroundEmoji: integers["nameBackgroundEmoji"],
            profileColor: integers["profileColor"].map(Int32.init), profileBackgroundEmoji: integers["profileBackgroundEmoji"], emojiStatus: integers["emojiStatus"])
        return result.isValid ? result : nil
    }

    public var values: [String: Any] {
        var result: [String: Any] = [:]
        if let nameColor { result["nameColor"] = nameColor }
        if let nameBackgroundEmoji { result["nameBackgroundEmoji"] = nameBackgroundEmoji }
        if let profileColor { result["profileColor"] = profileColor }
        if let profileBackgroundEmoji { result["profileBackgroundEmoji"] = profileBackgroundEmoji }
        if let emojiStatus { result["emojiStatus"] = emojiStatus }
        return result
    }
}
