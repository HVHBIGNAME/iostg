import Foundation
import Display
import TelegramCore

public enum WhitegramClassicSettings {
    private final class Relay {
        private var observer: NSObjectProtocol?
        init() {
            observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { _ in
                WhitegramClassicStyle.setEnabled(WhitegramPreferences.bool("classicInterface"))
            }
            WhitegramClassicStyle.setEnabled(WhitegramPreferences.bool("classicInterface"))
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    private static let relay = Relay()
    public static func install() { _ = relay }
}
