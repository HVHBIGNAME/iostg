import Foundation

public enum WhitegramBackgroundKind: String {
    case cover, video

    public var preferenceKey: String {
        switch self {
        case .cover: return "navigationProfileCoverFile"
        case .video: return "navigationVideoBackgroundFile"
        }
    }

    public var maximumBytes: Int { return self == .cover ? 8 * 1024 * 1024 : 40 * 1024 * 1024 }
}

public struct WhitegramBackgroundPolicy: Equatable {
    public let cover: String?
    public let video: String?
    public let videoInProfile: Bool

    public init(values: [String: Any]) {
        self.cover = Self.fileName(values[WhitegramBackgroundKind.cover.preferenceKey], kind: .cover)
        self.video = Self.fileName(values[WhitegramBackgroundKind.video.preferenceKey], kind: .video)
        self.videoInProfile = WhitegramNavigationPolicy.flag(values["videoBackgroundInProfile"])
    }

    public static func fileName(_ value: Any?, kind: WhitegramBackgroundKind) -> String? {
        guard let value = value as? String else { return nil }
        let suffix = kind == .cover ? ".jpg" : ".mov"
        guard value.hasSuffix(suffix), value.count == 36 + suffix.count,
              let uuid = UUID(uuidString: String(value.dropLast(suffix.count))),
              value == uuid.uuidString.lowercased() + suffix else { return nil }
        return value
    }

    public func profileFile(isOwnProfile: Bool) -> (String, WhitegramBackgroundKind)? {
        guard isOwnProfile else { return nil }
        if videoInProfile, let video { return (video, .video) }
        return cover.map { ($0, .cover) }
    }

    public static func shouldPlay(visible: Bool, attached: Bool, active: Bool, reduceMotion: Bool, lowPower: Bool) -> Bool {
        return visible && attached && active && !reduceMotion && !lowPower
    }
}

public enum WhitegramBackgroundStore {
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("WhitegramLocalBackgrounds", isDirectory: true)
    }

    public static func url(file: String, kind: WhitegramBackgroundKind) throws -> URL {
        guard WhitegramBackgroundPolicy.fileName(file, kind: kind) != nil else { throw invalidFile() }
        let root = try directory().resolvingSymlinksInPath()
        let result = root.appendingPathComponent(file)
        guard result.resolvingSymlinksInPath().deletingLastPathComponent() == root else { throw invalidFile() }
        let info = try result.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize,
              size > 0, size <= kind.maximumBytes else { throw invalidFile() }
        return result
    }

    /// Bytes have already passed image/video decoding in the picker. Filenames never come from the document provider.
    public static func save(_ data: Data, kind: WhitegramBackgroundKind, accountId: Int64, expectedScope: WhitegramPreferences.Scope) throws {
        guard !data.isEmpty, data.count <= kind.maximumBytes else { throw invalidFile() }
        guard try WhitegramPreferences.scope(accountId: accountId) == expectedScope else {
            throw NSError(domain: "WhitegramNavigation", code: 1, userInfo: [NSLocalizedDescriptionKey: "The account settings scope changed. Please choose the file again."])
        }
        let root = try directory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = UUID().uuidString.lowercased() + (kind == .cover ? ".jpg" : ".mov")
        try data.write(to: root.appendingPathComponent(file), options: .atomic)
        try WhitegramNavigationSettings.update([kind.preferenceKey: file], accountId: accountId, expectedScope: expectedScope)
    }

    public static func reset(_ kind: WhitegramBackgroundKind, accountId: Int64) throws {
        var changes: [String: Any] = [kind.preferenceKey: ""]
        if kind == .video { changes["videoBackgroundInProfile"] = false }
        // Other account/shared snapshots may still reference the old file.
        try WhitegramNavigationSettings.update(changes, accountId: accountId)
    }

    public static func invalidFile() -> NSError {
        return NSError(domain: "WhitegramBackground", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a readable still image (up to 8 MB) or a playable video (up to 40 MB and 60 seconds)."])
    }
}
