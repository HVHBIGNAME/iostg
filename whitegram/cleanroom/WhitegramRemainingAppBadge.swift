import Foundation
import UIKit
import AccountContext
import Display
import TelegramCore

public final class WhitegramRemainingAppBadgeBinding {
    private weak var window: Window1?
    private var observer: NSObjectProtocol?

    public init(context: AccountContext) {
        window = context.sharedContext.mainWindow
        observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func refresh() {
        guard let window else { return }
        let name = WhitegramRemainingPresentationPolicy.appBadgeName(WhitegramPreferences.string("appBadgeName"))
        guard let image = whitegramRemainingAppBadgeImage(name) ?? UIImage(bundleImageName: "Components/AppBadge") else { return }
        window.badgeView.image = image
        let width = window.badgeView.superview?.bounds.width ?? 0
        window.badgeView.frame = CGRect(x: floor((width - image.size.width) * 0.5), y: 5, width: image.size.width, height: image.size.height)
    }
}

func whitegramRemainingAppBadgeImage(_ name: String) -> UIImage? {
    guard name == "WGBadgeBlack" || name == "WGBadgeWhite" || name == "WGBadgePrimary" else { return nil }
    return UIImage(bundleImageName: "Components/" + name)
}
