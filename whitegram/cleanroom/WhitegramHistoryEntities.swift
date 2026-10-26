import Foundation

/// Portable subset of Telegram's Codable MessageTextEntity. Uses its exact keys
/// so conversion never passes 64-bit identifiers through JSON floating point.
public struct WhitegramHistoryEntity: Codable, Equatable {
    public let start: Int32
    public let end: Int32
    public let rawValue: Int32
    public let language: String?
    public let url: String?
    public let peerId: Int64?
    public let collapsed: Bool?
    public let fileId: Int64?
    public let format: Int32?
    public let date: Int32?
    public let customType: Int32?

    enum CodingKeys: String, CodingKey {
        case start, end, language, url, peerId, format, date
        case rawValue = "_rawValue", collapsed = "cl", fileId = "f", customType = "type"
    }

    public func isValid(in text: String) -> Bool {
        guard start >= 0, end > start, Int(end) <= text.utf16.count,
              (0...20).contains(rawValue) || rawValue == Int32.max,
              (language?.utf8.count ?? 0) <= 256, (url?.utf8.count ?? 0) <= 8192 else { return false }
        let utf16 = Array(text.utf16)
        for offset in [Int(start), Int(end)] where offset > 0 && offset < utf16.count {
            if (0xdc00...0xdfff).contains(utf16[offset]) && (0xd800...0xdbff).contains(utf16[offset - 1]) { return false }
        }
        switch rawValue {
        case 10: return url != nil
        case 11: return peerId.map { whitegramHistoryValidPeer(String($0)) } ?? false
        case 18: return fileId.map { $0 > 0 } ?? false
        case 19: return date.map { $0 >= 0 } ?? false
        case Int32.max: return customType != nil
        default: return true
        }
    }
}
