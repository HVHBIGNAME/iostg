import Foundation
import SwiftSignalKit
import TelegramCore

// Local profile edits change a dictionary, not the six interface flags.
func whitegramClientInterfaceProfileUpdates() -> Signal<Int, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: nil) { _ in
            subscriber.putNext(0)
        }
        subscriber.putNext(0)
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}
