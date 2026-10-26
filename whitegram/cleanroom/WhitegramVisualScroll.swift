import Foundation
import UIKit
import TelegramCore

public final class WhitegramVisualScrollEffect {
    private static let animationKey = "whitegram.visual.scroll"
    private weak var target: CALayer?
    private var state = WhitegramVisualScrollState()
    private var observation: WhitegramVisualObservation?

    public init() {
        observation = WhitegramVisualObservation { [weak self] in self?.reset() }
    }

    public func reset() {
        state.reset()
        target?.removeAnimation(forKey: Self.animationKey)
    }

    public func update(layer: CALayer, identity: String, rect: CGRect, visible: Bool) {
        if target !== layer { reset(); target = layer }
        let environment = WhitegramVisualEnvironment.shared
        let enabled = visible && environment.active && environment.policy.chatScrollAnimation && !environment.reduceMotion
        guard let displacement = state.update(identity: identity, position: Double(rect.minY), size: Double(rect.height), enabled: enabled) else {
            target?.removeAnimation(forKey: Self.animationKey)
            return
        }
        let translation = CASpringAnimation(keyPath: "position.y")
        translation.isAdditive = true
        translation.fromValue = displacement
        translation.toValue = 0.0
        translation.mass = 1.0
        translation.stiffness = 240.0
        translation.damping = 24.0
        translation.duration = min(0.5, translation.settlingDuration)

        let depth = CASpringAnimation(keyPath: "transform")
        depth.isAdditive = true
        let scale = CGFloat(WhitegramVisualPolicy.scrollScale(displacement: displacement))
        depth.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(scale, scale, 1.0))
        depth.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        depth.mass = translation.mass
        depth.stiffness = translation.stiffness
        depth.damping = translation.damping
        depth.duration = translation.duration
        let group = CAAnimationGroup()
        group.animations = [translation, depth]
        group.duration = translation.duration
        layer.add(group, forKey: Self.animationKey)
    }

    deinit { target?.removeAnimation(forKey: Self.animationKey) }
}
