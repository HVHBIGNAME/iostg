import Foundation
import UIKit
import TelegramCore

/// Applies additive scale animations, leaving model transforms, hit areas and layout frames intact.
public final class WhitegramVisualFisheye {
    private static let animationKey = "whitegram.visual.fisheye"
    private struct Item {
        weak var layer: CALayer?
        let center: CGFloat
    }
    private var items: [Item] = []
    private var center: CGFloat = 0.0
    private var enabled = false
    private var observation: WhitegramVisualObservation?

    public init() {
        observation = WhitegramVisualObservation { [weak self] in self?.refresh() }
    }

    public func update(layers: [(CALayer, CGFloat)], center: CGFloat, enabled: Bool) {
        let retained = Set(layers.map { ObjectIdentifier($0.0) })
        for item in items {
            if let layer = item.layer, !retained.contains(ObjectIdentifier(layer)) {
                layer.removeAnimation(forKey: Self.animationKey)
            }
        }
        items = layers.map { Item(layer: $0.0, center: $0.1) }
        self.center = center
        self.enabled = enabled
        refresh()
    }

    private func refresh() {
        let environment = WhitegramVisualEnvironment.shared
        for item in items {
            guard let layer = item.layer else { continue }
            let scale = WhitegramVisualPolicy.fisheyeScale(distance: Double(item.center - center),
                                                         enabled: enabled && environment.policy.fisheye && environment.active,
                                                         reduceMotion: environment.reduceMotion)
            if scale == 1.0 {
                layer.removeAnimation(forKey: Self.animationKey)
            } else {
                let animation = CABasicAnimation(keyPath: "transform")
                animation.isAdditive = true
                let transform = NSValue(caTransform3D: CATransform3DMakeScale(CGFloat(scale), CGFloat(scale), 1))
                animation.fromValue = transform
                animation.toValue = transform
                animation.duration = 0.0
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: Self.animationKey)
            }
        }
    }

    public func reset() {
        items.forEach { $0.layer?.removeAnimation(forKey: Self.animationKey) }
        items.removeAll()
    }

    deinit { reset() }
}
