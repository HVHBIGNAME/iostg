import Foundation
import SwiftSignalKit

public enum WhitegramClientInterfaceSettings {
    public static var current: WhitegramClientInterfacePolicy {
        return WhitegramClientInterfacePolicy(values: WhitegramPreferences.values())
    }

    public static func signal() -> Signal<WhitegramClientInterfacePolicy, NoError> {
        return Signal { subscriber in
            let observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: nil) { _ in
                subscriber.putNext(Self.current)
            }
            subscriber.putNext(Self.current)
            return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
        } |> distinctUntilChanged
    }
}
