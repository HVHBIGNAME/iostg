import Foundation
import UIKit

/// Isolated image/blur/tint stack. Never blurs the foreground controls or captures the screen.
public final class WhitegramVisualBackdrop: UIView {
    private let imageView = UIImageView()
    private let gradient = CAGradientLayer()
    private var blurView: UIVisualEffectView?
    private let tintView = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        layer.addSublayer(gradient)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        addSubview(tintView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(image: UIImage?, colors: [UIColor], blurred: Bool, tint: UIColor, base: UIColor) {
        backgroundColor = base
        imageView.image = image
        gradient.colors = colors.map { $0.cgColor }
        gradient.isHidden = colors.isEmpty
        if blurred && image != nil {
            if blurView == nil {
                let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
                view.isUserInteractionEnabled = false
                insertSubview(view, belowSubview: tintView)
                blurView = view
            }
        } else {
            blurView?.removeFromSuperview()
            blurView = nil
        }
        tintView.backgroundColor = tint
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        imageView.frame = bounds
        blurView?.frame = bounds
        tintView.frame = bounds
    }

    public func clear() {
        imageView.image = nil
        gradient.colors = nil
        blurView?.removeFromSuperview()
        blurView = nil
        removeFromSuperview()
    }
}

/// The player owns this adapter; nil artwork and identity changes clear it synchronously.
public final class WhitegramVisualAlbumArt {
    private weak var host: UIView?
    private weak var background: CALayer?
    private var backdrop: WhitegramVisualBackdrop?
    private var image: UIImage?
    private var frame = CGRect.zero
    private var base = UIColor.white
    private var observation: WhitegramVisualObservation?

    public init() {
        observation = WhitegramVisualObservation { [weak self] in self?.refresh() }
    }

    public func setImage(_ image: UIImage?) {
        self.image = image
        refresh()
    }

    public func update(host: UIView, above background: CALayer, frame: CGRect, base: UIColor) {
        self.host = host
        self.background = background
        self.frame = frame
        self.base = base
        refresh()
    }

    private func refresh() {
        let environment = WhitegramVisualEnvironment.shared
        guard environment.policy.albumArtBlur, !environment.reduceTransparency,
              let image, let host, let background, frame.width > 0, frame.height > 0 else {
            backdrop?.clear()
            backdrop = nil
            return
        }
        let view = backdrop ?? WhitegramVisualBackdrop(frame: frame)
        backdrop = view
        if view.superview !== host {
            host.addSubview(view)
            host.layer.insertSublayer(view.layer, above: background)
        }
        view.frame = frame
        view.layer.cornerRadius = 12.0
        view.update(image: image, colors: [], blurred: true, tint: base.withAlphaComponent(0.72), base: base)
    }

    deinit { backdrop?.clear() }
}
