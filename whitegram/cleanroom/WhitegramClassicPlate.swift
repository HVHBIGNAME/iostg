import UIKit

/// Reuses Telegram's actual pre-glass navigation background and a hairline divider.
public final class WhitegramClassicPlate: UIView {
    private let background = NavigationBackgroundNode(color: .clear)
    private let separator = UIView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.accessibilityElementsHidden = true
        self.addSubview(self.background.view)
        self.addSubview(self.separator)
        self.isHidden = true
    }
    required public init?(coder: NSCoder) { return nil }

    public func update(size: CGSize, color: UIColor, separatorColor: UIColor, separatorAtTop: Bool, enabled: Bool, transition: ContainedViewLayoutTransition) {
        self.isHidden = !enabled
        guard enabled else { return }
        transition.updateFrame(node: self.background, frame: CGRect(origin: .zero, size: size))
        self.background.updateColor(color: color, transition: transition)
        self.background.update(size: size, transition: transition)
        self.separator.backgroundColor = separatorColor
        let pixel = 1.0 / UIScreen.main.scale
        self.separator.frame = CGRect(x: 0, y: separatorAtTop ? 0 : max(0, size.height - pixel), width: size.width, height: pixel)
    }
}
