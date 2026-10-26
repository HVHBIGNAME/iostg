import Foundation

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

@main
struct WhitegramAccountSettingsChecks {
    static func main() throws {
        let defaults = UserDefaults.standard
        if CommandLine.arguments.contains("--resume") {
            precondition(WhitegramPreferences.string("customFontName") == "private B")
            precondition(WhitegramPreferences.activateAccount(Int64.max))
            precondition(WhitegramPreferences.string("customFontName") == "private A")
            print("Account settings: persisted active/private profiles restored in a new process.")
            return
        }
        if CommandLine.arguments.contains("--legacy") {
            defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
            defaults.set(["42": true], forKey: "wg_separateAccountSettings.v1")
            defaults.set(true, forKey: "wg_ghostModeEnabled_account_42")
            WhitegramPreferences.registerProfileMirrors(["wg_ghostModeEnabled"])
            precondition(WhitegramPreferences.activateAccount(42))
            precondition(WhitegramPreferences.bool("ghostModeEnabled"))
            precondition(defaults.bool(forKey: "wg_ghostModeEnabled"))
            precondition(WhitegramPreferences.activateAccount(nil))
            precondition(!WhitegramPreferences.bool("ghostModeEnabled"))
            print("Account settings: original decimal account mode/suffixed primitive migration passed.")
            return
        }
        defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
        let a = Int64.max
        let b = Int64.min
        WhitegramSettingsArchiveStore.registerProfileMirrors()
        WhitegramPreferences.registerProfileMirrors(["wg_geminiApiKey", "wg_activeWhitegramAccountId"])
        precondition(WhitegramPreferences.activateAccount(nil))
        precondition(WhitegramPreferences.update(["ghostModeEnabled": true, "customFontName": "shared", "geminiApiKey": "secret"]))
        defaults.set(Data("{\"compactPinnedMessagesPanel\":true}".utf8), forKey: "WhiteGramChatSettings.v1")
        precondition(WhitegramPreferences.activateAccount(a))
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: a)
        precondition(WhitegramPreferences.bool("ghostModeEnabled"))
        precondition(WhitegramPreferences.update(["ghostModeEnabled": false, "customFontName": "private A", "onlyA": true]))
        defaults.set(Data("{\"compactPinnedMessagesPanel\":false}".utf8), forKey: "WhiteGramChatSettings.v1")
        precondition(WhitegramPreferences.activateAccount(b))
        precondition(WhitegramPreferences.bool("ghostModeEnabled"))
        precondition(WhitegramPreferences.string("customFontName") == "shared")
        precondition(defaults.object(forKey: "wg_onlyA") == nil)
        precondition(defaults.bool(forKey: "wg_ghostModeEnabled"))
        let sharedChat = try JSONSerialization.jsonObject(with: defaults.data(forKey: "WhiteGramChatSettings.v1")!) as? [String: Bool]
        precondition(sharedChat == ["compactPinnedMessagesPanel": true])
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: b)
        precondition(WhitegramPreferences.set("private B", for: "customFontName"))
        precondition(WhitegramPreferences.activateAccount(a))
        precondition(!WhitegramPreferences.bool("ghostModeEnabled"))
        precondition(WhitegramPreferences.string("customFontName") == "private A")
        let privateChat = try JSONSerialization.jsonObject(with: defaults.data(forKey: "WhiteGramChatSettings.v1")!) as? [String: Bool]
        precondition(privateChat == ["compactPinnedMessagesPanel": false])
        let scopedData = defaults.data(forKey: WhitegramPreferences.accountProfilesKey)!
        precondition(!WhitegramPreferences.update(["ghostModeEnabled": true, "invalid": Date()]))
        precondition(defaults.data(forKey: WhitegramPreferences.accountProfilesKey) == scopedData)
        precondition(!WhitegramPreferences.bool("ghostModeEnabled"))
        let exported = try WhitegramSettingsArchiveStore.exportSettings(scope: .account(a))
        precondition(exported.archive.values["ghostModeEnabled"] as? Bool == false)
        precondition(exported.archive.values["geminiApiKey"] == nil)
        let archive = try WhitegramSettingsArchive(data: Data("{\"format\":\"whitegram.settings.port\",\"version\":1,\"createdAt\":1,\"settings\":{\"ghostModeEnabled\":true,\"hideStories\":true}}".utf8))
        _ = try WhitegramSettingsArchiveStore.importSettings(archive, scope: .account(b))
        precondition(!WhitegramPreferences.bool("ghostModeEnabled"))
        precondition(!defaults.bool(forKey: "wg_ghostModeEnabled"))
        precondition(WhitegramPreferences.activateAccount(b))
        precondition(WhitegramPreferences.bool("ghostModeEnabled"))
        precondition(WhitegramPreferences.bool("hideStories"))
        try WhitegramPreferences.setUsesSeparateSettings(false, accountId: b)
        precondition(WhitegramPreferences.string("customFontName") == "shared")
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: b)
        precondition(WhitegramPreferences.string("customFontName") == "private B")
        precondition(WhitegramPreferences.string("geminiApiKey") == "secret")
        precondition(defaults.string(forKey: "wg_geminiApiKey") == "secret")
        let notifications = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: nil) { _ in notifications.increment() }
        _ = try WhitegramSettingsArchiveStore.importSettings(archive, scope: .account(b))
        let first = notifications.value
        _ = try WhitegramSettingsArchiveStore.importSettings(archive, scope: .account(b))
        precondition(notifications.value == first)
        NotificationCenter.default.removeObserver(observer)
        let original = defaults.data(forKey: WhitegramPreferences.accountProfilesKey)!
        defaults.set(Data("invalid".utf8), forKey: WhitegramPreferences.accountProfilesKey)
        precondition(!WhitegramPreferences.set(false, for: "ghostModeEnabled"))
        precondition(!WhitegramPreferences.activateAccount(a))
        precondition(defaults.data(forKey: WhitegramPreferences.accountProfilesKey) == Data("invalid".utf8))
        defaults.set(original, forKey: WhitegramPreferences.accountProfilesKey)
        precondition(WhitegramPreferences.activateAccount(a))
        precondition(WhitegramPreferences.string("customFontName") == "private A")
        let sharedUpdate = try WhitegramSettingsArchive(data: Data("{\"format\":\"whitegram.settings.port\",\"version\":1,\"createdAt\":1,\"settings\":{\"customFontName\":\"new shared\"}}".utf8))
        _ = try WhitegramSettingsArchiveStore.importSettings(sharedUpdate, scope: .shared)
        precondition(WhitegramPreferences.string("customFontName") == "private A")
        precondition(WhitegramPreferences.activateAccount(nil))
        precondition(WhitegramPreferences.string("customFontName") == "new shared")
        precondition(WhitegramPreferences.activateAccount(a))
        defaults.set("invalid-object", forKey: WhitegramPreferences.accountProfilesKey)
        precondition(!WhitegramPreferences.activateAccount(b))
        precondition(defaults.string(forKey: WhitegramPreferences.accountProfilesKey) == "invalid-object")
        defaults.set(original, forKey: WhitegramPreferences.accountProfilesKey)
        precondition(WhitegramPreferences.activateAccount(b))
        defaults.synchronize()
        print("Account settings: isolation, mirrors, private-profile retention, exact Int64, pinned import scope, secrets and malformed-store preservation passed.")
    }
}
