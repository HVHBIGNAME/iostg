import Foundation

@main
enum WhitegramNavigationTests {
    static var checks = 0

    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { fatalError(message) }
        checks += 1
    }

    static func main() throws {
        let a: Int64 = 700000001
        let b: Int64 = 700000002
        let cover = "ac238b1d-435e-4c6d-9ab4-eac0815f0aed.jpg"
        let video = "ac238b1d-435e-4c6d-9ab4-eac0815f0aed.mov"
        if CommandLine.arguments.contains("--reload") {
            try expect(WhitegramNavigationSettings.policy(accountId: a).separateProfileTab, "Account A survives process restart")
            try expect(!WhitegramNavigationSettings.policy(accountId: b).separateProfileTab, "Account B does not inherit A")
            try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).cover == cover, "Cover survives restart")
            try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).video == nil, "Video reset survives restart")
            try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: b)).video == video, "Other profile media survives reset")
            print("Navigation reload checks: \(checks)")
            return
        }
        try expect(!WhitegramNavigationPolicy(values: [:]).hideBottomTabBar, "Missing flag defaults off")
        for invalid: Any in [1, 0, "true", NSNull(), [true]] {
            try expect(!WhitegramNavigationPolicy(values: ["hideBottomTabBar": invalid]).hideBottomTabBar, "Only canonical booleans accepted")
        }
        try expect(WhitegramNavigationPolicy(values: ["hideBottomTabBar": true]).hideBottomTabBar, "True enables hidden bar")
        try expect(WhitegramNavigationPolicy.selection(previous: "settings", available: ["chats", "settings", "profile"], fallback: "chats") == 1, "Keep Settings selected when adding profile")
        try expect(WhitegramNavigationPolicy.selection(previous: "profile", available: ["contacts", "chats", "settings"], fallback: "chats") == 1, "Removed profile falls back to Chats")
        try expect(WhitegramNavigationPolicy.selection(previous: nil, available: [], fallback: "chats") == nil, "Empty tabs cannot select")
        try expect(WhitegramBackgroundPolicy.fileName(cover, kind: .cover) == cover, "Managed still filename")
        try expect(WhitegramBackgroundPolicy.fileName(video, kind: .video) == video, "Managed video filename")
        for invalid: Any in ["../" + cover, "/tmp/" + cover, "https://example.com/" + cover, cover.uppercased(), "", true, video] {
            try expect(WhitegramBackgroundPolicy.fileName(invalid, kind: .cover) == nil, "Reject non-managed cover reference")
        }
        let policy = WhitegramBackgroundPolicy(values: ["navigationProfileCoverFile": cover, "navigationVideoBackgroundFile": video, "videoBackgroundInProfile": true])
        try expect(policy.profileFile(isOwnProfile: false) == nil, "Never decorate another user's profile")
        try expect(policy.profileFile(isOwnProfile: true)?.0 == video, "Video takes priority on own profile")
        let still = WhitegramBackgroundPolicy(values: ["navigationProfileCoverFile": cover, "navigationVideoBackgroundFile": video, "videoBackgroundInProfile": false])
        try expect(still.profileFile(isOwnProfile: true)?.0 == cover, "Disabling profile video restores cover")
        for mask in 0..<32 {
            let visible = mask & 1 != 0
            let attached = mask & 2 != 0
            let active = mask & 4 != 0
            let motion = mask & 8 != 0
            let power = mask & 16 != 0
            try expect(WhitegramBackgroundPolicy.shouldPlay(visible: visible, attached: attached, active: active, reduceMotion: motion, lowPower: power) == (mask == 7), "Visibility, app and power gates")
        }
        try expect(WhitegramPreferences.activateAccount(nil), "Select shared settings")
        try expect(WhitegramPreferences.update(["separateProfileTab": false, "hideBottomTabBar": false, "navigationVideoBackgroundFile": video, "videoBackgroundInProfile": true]), "Seed shared snapshot")
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: a)
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: b)
        try WhitegramNavigationSettings.update(["separateProfileTab": true, "hideBottomTabBar": true, "navigationProfileCoverFile": cover], accountId: a)
        try expect(WhitegramPreferences.activateAccount(b), "Activate B")
        try expect(!WhitegramPreferences.bool("separateProfileTab"), "Foreground uses B")
        try expect(WhitegramNavigationSettings.policy(accountId: a).separateProfileTab, "Background A reads its own settings")
        try WhitegramBackgroundStore.reset(.video, accountId: a)
        try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).video == nil, "Reset clears A video")
        try expect(!WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).videoInProfile, "Reset clears A profile-video flag")
        try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).cover == cover, "Reset video preserves still cover")
        try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: b)).video == video, "Reset preserves other account video")
        let captured = try WhitegramPreferences.scope(accountId: a)
        try WhitegramPreferences.setUsesSeparateSettings(false, accountId: a)
        do {
            try WhitegramNavigationSettings.update(["hideBottomTabBar": true], accountId: a, expectedScope: captured)
            fatalError("Stale picker scope accepted")
        } catch { checks += 1 }
        try expect(!WhitegramNavigationSettings.policy(accountId: a).hideBottomTabBar, "Stale picker did not mutate shared settings")
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: a)
        try expect(WhitegramNavigationSettings.policy(accountId: a).hideBottomTabBar, "Private snapshot restores on re-enable")
        try WhitegramBackgroundStore.reset(.cover, accountId: b)
        try expect(WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).cover == cover, "Reset other account cover is isolated")
        let storage = try WhitegramBackgroundStore.directory()
        guard let scratch = ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
              storage.path.hasPrefix(scratch + "/") else { fatalError("Media storage test must stay inside scratch") }
        // Store-level I/O only. Apple image/video decoding is a separate device check.
        let payload = Data([0x12, 0x34, 0x56])
        try WhitegramBackgroundStore.save(payload, kind: .cover, accountId: a, expectedScope: captured)
        guard let stored = try WhitegramBackgroundPolicy(values: WhitegramNavigationSettings.values(accountId: a)).cover else { fatalError("No committed media reference") }
        let storedURL = try WhitegramBackgroundStore.url(file: stored, kind: .cover)
        try expect(Data(contentsOf: storedURL) == payload, "Atomic media write preserves bytes")
        try WhitegramBackgroundStore.reset(.cover, accountId: a)
        try expect(FileManager.default.fileExists(atPath: storedURL.path), "Reset retains files possibly used by another profile")
        let alias = "15299e2f-46b1-407d-ae62-50d71f856034.jpg"
        try FileManager.default.createSymbolicLink(at: storage.appendingPathComponent(alias), withDestinationURL: storedURL)
        do { _ = try WhitegramBackgroundStore.url(file: alias, kind: .cover); fatalError("Symlink accepted") }
        catch { checks += 1 }
        let beforeFiles = try FileManager.default.contentsOfDirectory(atPath: storage.path).sorted()
        do { try WhitegramBackgroundStore.save(Data(count: WhitegramBackgroundKind.cover.maximumBytes + 1), kind: .cover, accountId: a, expectedScope: captured); fatalError("Oversized file accepted") }
        catch { checks += 1 }
        try expect(FileManager.default.contentsOfDirectory(atPath: storage.path).sorted() == beforeFiles, "Invalid media never creates a file")
        try WhitegramNavigationSettings.update(["navigationProfileCoverFile": cover], accountId: a)
        // swift-corelibs does not guarantee a flush when a command-line process exits immediately.
        try expect(UserDefaults.standard.synchronize(), "Flush the test defaults before the restart probe")
        print("Navigation Foundation checks: \(checks)")
    }
}
