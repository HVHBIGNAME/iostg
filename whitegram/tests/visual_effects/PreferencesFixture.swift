import Foundation

public enum WhitegramPreferences {
    public static let updatedNotification = Notification.Name("WhitegramSettingsStateUpdated")
    public static var testValues: [String: Any] = [:]
    public static func values() -> [String: Any] { return testValues }
    public static func set(_ values: [String: Any]) {
        testValues = values
        NotificationCenter.default.post(name: updatedNotification, object: nil)
    }
}
