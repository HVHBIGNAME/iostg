import Foundation
import UIKit
import TelegramCore

final class WhitegramClientInterfaceReactionGlow {
    private weak var layer: CALayer?
    private var color = UIColor.clear
    private var isTag = false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.apply()
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func update(layer: CALayer, color: UIColor, isTag: Bool) {
        self.layer = layer
        self.color = color
        self.isTag = isTag
        apply()
    }

    private func apply() {
        guard let layer else { return }
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = WhitegramClientInterfaceSettings.current.glowOpacity(isTag: isTag)
        layer.shadowRadius = 7
        layer.shadowOffset = .zero
        layer.shadowPath = UIBezierPath(roundedRect: layer.bounds, cornerRadius: layer.bounds.height * 0.5).cgPath
    }
}
