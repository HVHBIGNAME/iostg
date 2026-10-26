import Foundation
import UIKit
import TelegramCore

public final class WhitegramVisualParticles: UIView {
    private let placement: WhitegramVisualPolicy.Placement
    private var emitter: CAEmitterLayer?
    private var appliedPolicy: WhitegramVisualPolicy?
    private var observation: WhitegramVisualObservation?
    private var visible = true

    public init(placement: WhitegramVisualPolicy.Placement) {
        self.placement = placement
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        observation = WhitegramVisualObservation { [weak self] in self?.refresh() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func setVisible(_ visible: Bool) {
        self.visible = visible
        refresh()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
        if let emitter {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: -12.0)
            emitter.emitterSize = CGSize(width: bounds.width * 1.5, height: 1.0)
            CATransaction.commit()
        }
    }

    private func refresh() {
        let environment = WhitegramVisualEnvironment.shared
        let policy = environment.policy
        guard policy.showsParticles(in: placement, visible: visible && window != nil && bounds.width > 0 && bounds.height > 0,
                                    active: environment.active, reduceMotion: environment.reduceMotion, lowPower: environment.lowPower) else {
            stop()
            return
        }
        if emitter != nil && appliedPolicy == policy { return }
        stop()
        guard let image = Self.particleImage(policy.particle) else { return }
        let cell = CAEmitterCell()
        cell.contents = image.cgImage
        cell.birthRate = Float((policy.particle == .snow ? 10.0 : 7.0) * policy.densityMultiplier)
        cell.lifetime = Float(min(24.0, max(6.0, Double(bounds.height) / (32.0 * policy.speedMultiplier) + 3.0)))
        cell.velocity = CGFloat(32.0 * policy.speedMultiplier)
        cell.velocityRange = CGFloat(12.0 * policy.speedMultiplier)
        cell.emissionLongitude = .pi / 2.0
        cell.emissionRange = .pi / 8.0
        cell.yAcceleration = CGFloat(3.0 * policy.speedMultiplier)
        cell.xAcceleration = policy.particle == .autumn ? CGFloat(3.0 * policy.speedMultiplier) : 0.0
        cell.spin = policy.particle == .autumn ? 0.4 : 0.1
        cell.spinRange = 0.5
        cell.scale = policy.particle == .snow ? 0.25 : 0.45
        cell.scaleRange = 0.15
        cell.alphaSpeed = -0.015
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.renderMode = .unordered
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -12.0)
        emitter.emitterSize = CGSize(width: bounds.width * 1.5, height: 1.0)
        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
        self.emitter = emitter
        appliedPolicy = policy
    }

    private func stop() {
        emitter?.birthRate = 0
        emitter?.emitterCells = nil
        emitter?.removeFromSuperlayer()
        emitter = nil
        appliedPolicy = nil
    }

    private static func particleImage(_ particle: WhitegramVisualPolicy.Particle) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format)
        switch particle {
        case .off:
            return nil
        case .snow:
            return renderer.image { _ in
                UIColor.white.withAlphaComponent(0.85).setFill()
                UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 18, height: 18)).fill()
            }
        case .autumn:
            return renderer.image { _ in
                UIColor(red: 0.86, green: 0.43, blue: 0.14, alpha: 0.9).setFill()
                let leaf = UIBezierPath()
                leaf.move(to: CGPoint(x: 3, y: 21))
                leaf.addCurve(to: CGPoint(x: 21, y: 3), controlPoint1: CGPoint(x: -2, y: 4), controlPoint2: CGPoint(x: 10, y: 1))
                leaf.addCurve(to: CGPoint(x: 3, y: 21), controlPoint1: CGPoint(x: 23, y: 18), controlPoint2: CGPoint(x: 16, y: 25))
                leaf.fill()
            }
        }
    }

    deinit { stop() }
}
