// Linux test double for animation ownership and notifications; this does not render UIKit.
@_exported import Foundation

public struct CATransform3D {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
}
public let CATransform3DIdentity = CATransform3D(x: 1, y: 1, z: 1)
public func CATransform3DMakeScale(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D { return CATransform3D(x: x, y: y, z: z) }
public extension NSValue {
    convenience init(caTransform3D: CATransform3D) { self.init(point: CGPoint(x: caTransform3D.x, y: caTransform3D.y)) }
}
public enum CAMediaTimingFillMode { case both }
open class CAAnimation {
    public var duration: Double = 0
    public var fillMode: CAMediaTimingFillMode = .both
    public var isRemovedOnCompletion = true
    public init() {}
}
open class CABasicAnimation: CAAnimation {
    public let keyPath: String?
    public var fromValue: Any?
    public var toValue: Any?
    public var isAdditive = false
    public init(keyPath: String?) { self.keyPath = keyPath; super.init() }
}
public final class CASpringAnimation: CABasicAnimation {
    public var mass: CGFloat = 0
    public var stiffness: CGFloat = 0
    public var damping: CGFloat = 0
    public var settlingDuration: Double { return 0.8 }
}
public final class CAAnimationGroup: CAAnimation {
    public var animations: [CAAnimation]?
}
open class CALayer {
    public var transform = CATransform3DIdentity
    public var frame = CGRect.zero
    public var backgroundColor: CGColor?
    public var isHidden = false
    public var cornerRadius: CGFloat = 0
    public var shadowColor: CGColor?
    public var shadowOpacity: Float = 0
    public var shadowRadius: CGFloat = 0
    public var shadowOffset = CGSize.zero
    public var shadowPath: CGPath?
    public weak var superlayer: CALayer?
    public private(set) var sublayers: [CALayer] = []
    public private(set) var animations: [String: CAAnimation] = [:]
    public init() {}
    public func add(_ animation: CAAnimation, forKey key: String?) { animations[key ?? ""] = animation }
    public func removeAnimation(forKey key: String) { animations.removeValue(forKey: key) }
    public func addSublayer(_ layer: CALayer) { layer.removeFromSuperlayer(); sublayers.append(layer); layer.superlayer = self }
    public func insertSublayer(_ layer: CALayer, below other: CALayer) {
        layer.removeFromSuperlayer()
        let index = sublayers.firstIndex { $0 === other } ?? 0
        sublayers.insert(layer, at: index); layer.superlayer = self
    }
    public func insertSublayer(_ layer: CALayer, above other: CALayer) {
        layer.removeFromSuperlayer()
        let index = sublayers.firstIndex { $0 === other }.map { $0 + 1 } ?? sublayers.count
        sublayers.insert(layer, at: index); layer.superlayer = self
    }
    public func removeFromSuperlayer() { superlayer?.sublayers.removeAll { $0 === self }; superlayer = nil }
}
public final class CAGradientLayer: CALayer { public var colors: [Any]? }
public enum CAEmitterLayerEmitterShape { case line }
public enum CAEmitterLayerEmitterMode { case outline }
public enum CAEmitterLayerRenderMode { case unordered }
public final class CAEmitterLayer: CALayer {
    public var emitterShape: CAEmitterLayerEmitterShape = .line
    public var emitterMode: CAEmitterLayerEmitterMode = .outline
    public var renderMode: CAEmitterLayerRenderMode = .unordered
    public var emitterPosition = CGPoint.zero
    public var emitterSize = CGSize.zero
    public var emitterCells: [CAEmitterCell]?
    public var birthRate: Float = 1
}
public final class CAEmitterCell {
    public var contents: Any?
    public var birthRate: Float = 0
    public var lifetime: Float = 0
    public var velocity: CGFloat = 0
    public var velocityRange: CGFloat = 0
    public var emissionLongitude: CGFloat = 0
    public var emissionRange: CGFloat = 0
    public var yAcceleration: CGFloat = 0
    public var xAcceleration: CGFloat = 0
    public var spin: CGFloat = 0
    public var spinRange: CGFloat = 0
    public var scale: CGFloat = 0
    public var scaleRange: CGFloat = 0
    public var alphaSpeed: Float = 0
    public init() {}
}
public enum CATransaction {
    public static func begin() {}
    public static func setDisableActions(_ value: Bool) {}
    public static func commit() {}
}
open class UIView {
    public let layer = CALayer()
    public var frame: CGRect { didSet { layer.frame = frame } }
    public var bounds: CGRect { return CGRect(origin: .zero, size: frame.size) }
    public var isUserInteractionEnabled = true
    public var isAccessibilityElement = true
    public var accessibilityElementsHidden = false
    public var clipsToBounds = false
    public var backgroundColor: UIColor?
    public weak var superview: UIView?
    public private(set) var subviews: [UIView] = []
    public var window: UIWindow? { return self as? UIWindow ?? superview?.window }
    public init(frame: CGRect) { self.frame = frame }
    public convenience init() { self.init(frame: .zero) }
    public required init?(coder: NSCoder) { frame = .zero }
    public func addSubview(_ view: UIView) {
        view.removeFromSuperview(); subviews.append(view); view.superview = self
        layer.addSublayer(view.layer); view.didMoveToWindow()
    }
    public func insertSubview(_ view: UIView, at index: Int) {
        view.removeFromSuperview()
        if index < subviews.count { layer.insertSublayer(view.layer, below: subviews[index].layer) } else { layer.addSublayer(view.layer) }
        subviews.insert(view, at: index); view.superview = self; view.didMoveToWindow()
    }
    public func insertSubview(_ view: UIView, belowSubview other: UIView) { insertSubview(view, at: subviews.firstIndex { $0 === other } ?? 0) }
    public func removeFromSuperview() {
        let wasAttached = superview != nil
        superview?.subviews.removeAll { $0 === self }; superview = nil; layer.removeFromSuperlayer()
        if wasAttached { didMoveToWindow() }
    }
    public func convert(_ rect: CGRect, to: UIView?) -> CGRect { return rect.offsetBy(dx: frame.minX, dy: frame.minY) }
    public func setNeedsLayout() {}
    open func layoutSubviews() {}
    open func didMoveToWindow() {}
}
open class UIWindow: UIView {}
public enum UIViewContentMode { case scaleAspectFill }
open class UIImageView: UIView {
    public var image: UIImage?
    public var contentMode: UIViewContentMode = .scaleAspectFill
}
open class UIVisualEffect {}
public final class UIBlurEffect: UIVisualEffect {
    public enum Style { case regular }
    public init(style: Style) {}
}
public final class UIVisualEffectView: UIView {
    public init(effect: UIVisualEffect?) { super.init(frame: .zero) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
public final class CGColor {}
public final class UIColor {
    public static let white = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let black = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let clear = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
    public let alpha: CGFloat
    public let cgColor = CGColor()
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.alpha = alpha }
    public func withAlphaComponent(_ alpha: CGFloat) -> UIColor { return UIColor(red: 1, green: 1, blue: 1, alpha: alpha) }
    public func setFill() {}
}
public final class CGPath {}
public final class UIBezierPath {
    public let cgPath = CGPath()
    public init() {}
    public init(ovalIn: CGRect) {}
    public func move(to: CGPoint) {}
    public func addCurve(to: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {}
    public func fill() {}
}
public final class CGImage { public init() {} }
public final class UIImage {
    public var cgImage: CGImage? = CGImage()
    public init() {}
}
public final class UIGraphicsImageRendererFormat {
    public var scale: CGFloat = 1
    public init() {}
}
public final class UIGraphicsImageRenderer {
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    public func image(actions: (Int) -> Void) -> UIImage { actions(0); return UIImage() }
}
public enum CGImageAlphaInfo: UInt32 { case premultipliedLast = 1 }
public final class CGColorSpace {}
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { return CGColorSpace() }
public enum CGInterpolationQuality { case high }
public final class CGContext {
    private let data: UnsafeMutableRawPointer?
    public var interpolationQuality: CGInterpolationQuality = .high
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) { self.data = data }
    public func draw(_ image: CGImage, in rect: CGRect) {
        let bytes = data!.assumingMemoryBound(to: UInt8.self)
        for i in 0 ..< 4 { bytes[i] = 255 }
    }
}
public enum UIAccessibility {
    public static var isReduceMotionEnabled = false
    public static var isReduceTransparencyEnabled = false
    public static let reduceMotionStatusDidChangeNotification = Notification.Name("TestReduceMotion")
    public static let reduceTransparencyStatusDidChangeNotification = Notification.Name("TestReduceTransparency")
}
public enum UIApplication {
    public static let didBecomeActiveNotification = Notification.Name("TestBecameActive")
    public static let willResignActiveNotification = Notification.Name("TestResignedActive")
}
public enum TestPowerState { public static var lowPower = false }
public extension ProcessInfo { var isLowPowerModeEnabled: Bool { return TestPowerState.lowPower } }
public extension Notification.Name { static let NSProcessInfoPowerStateDidChange = Notification.Name("TestPowerChanged") }
