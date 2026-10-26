import Foundation

public enum WhitegramPreferences {
    public static let updatedNotification = Notification.Name("RemainingTestPreferencesUpdated")
    public static var hidden = false
    public static func bool(_ key: String) -> Bool { key == "hideWhitegramUserBadge" && hidden }
}
