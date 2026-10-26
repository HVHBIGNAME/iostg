import Foundation
import UIKit

public final class WhitegramVisualProfile {
    private weak var host: UIView?
    private weak var avatarView: UIView?
    private var backdrop: WhitegramVisualBackdrop?
    private var glow: CALayer?
    private var identity: String?
    private var image: UIImage?
    private var imageColor: UIColor?
    private var frame = CGRect.zero
    private var colors: [UIColor] = []
    private var base = UIColor.white
    private var expanded = false
    private var suppressed = true
    private var hasPhoto = false
    private var observation: WhitegramVisualObservation?

    public init() {
        observation = WhitegramVisualObservation { [weak self] in self?.refresh() }
    }

    public func setImage(_ image: UIImage?) {
        self.image = hasPhoto ? image : nil
        imageColor = self.image.flatMap(Self.averageColor)
        refresh()
    }

    public func update(host: UIView, avatarView: UIView, frame: CGRect, identity: String?, hasPhoto: Bool,
                       colors: [UIColor], base: UIColor, expanded: Bool, suppressed: Bool) {
        if self.identity != identity || !hasPhoto {
            image = nil
            imageColor = nil
            backdrop?.clear()
            glow?.removeFromSuperlayer()
        }
        self.identity = identity
        self.host = host
        self.avatarView = avatarView
        self.frame = frame
        self.hasPhoto = hasPhoto
        self.colors = colors
        self.base = base
        self.expanded = expanded
        self.suppressed = suppressed
        refresh()
    }

    private func refresh() {
        let environment = WhitegramVisualEnvironment.shared
        let policy = environment.policy
        let showImage = policy.showsAvatarBackground(expanded: expanded, hasImage: image != nil, suppressed: suppressed) && !environment.reduceTransparency
        let showColor = policy.profileColorEffect && !colors.isEmpty && !suppressed
        if let host, frame.width > 0, frame.height > 0, showImage || showColor {
            let view = backdrop ?? WhitegramVisualBackdrop(frame: frame)
            backdrop = view
            if view.superview !== host { host.insertSubview(view, at: 0) }
            view.frame = frame
            view.update(image: showImage ? image : nil, colors: showColor ? colors : [],
                        blurred: !policy.avatarBlurReduced,
                        tint: showImage && policy.avatarBlurTint ? UIColor.black.withAlphaComponent(0.35) : .clear,
                        base: base)
        } else {
            backdrop?.clear()
            backdrop = nil
        }
        updateGlow(enabled: policy.avatarGlow && !suppressed && !expanded && image != nil)
    }

    private func updateGlow(enabled: Bool) {
        guard enabled, let avatarView, let parent = avatarView.superview else {
            glow?.removeFromSuperlayer()
            glow = nil
            return
        }
        let layer = glow ?? CALayer()
        glow = layer
        if layer.superlayer !== parent.layer { parent.layer.insertSublayer(layer, below: avatarView.layer) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = avatarView.convert(avatarView.bounds, to: parent)
        layer.frame = rect
        layer.backgroundColor = UIColor.clear.cgColor
        layer.shadowColor = (imageColor ?? colors.first ?? base).cgColor
        layer.shadowOpacity = 0.65
        layer.shadowRadius = 16.0
        layer.shadowOffset = .zero
        layer.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: rect.size)).cgPath
        CATransaction.commit()
    }

    private static func averageColor(_ image: UIImage) -> UIColor? {
        guard let source = image.cgImage else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn, pixel[3] > 0 else { return nil }
        let alpha = CGFloat(pixel[3])
        return UIColor(red: CGFloat(pixel[0]) / alpha, green: CGFloat(pixel[1]) / alpha, blue: CGFloat(pixel[2]) / alpha, alpha: 1.0)
    }

    deinit {
        backdrop?.clear()
        glow?.removeFromSuperlayer()
    }
}
