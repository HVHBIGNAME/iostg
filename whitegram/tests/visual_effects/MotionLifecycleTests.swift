import Foundation
import UIKit
import TelegramCore

@main
enum MotionLifecycleTests {
    static func main() {
        WhitegramPreferences.set(["chatScrollAnimation": true, "wgBubbleFisheyeEffect": true])
        let layer = CALayer()
        layer.transform = CATransform3DMakeScale(-1, -1, 1)
        layer.add(CABasicAnimation(keyPath: "opacity"), forKey: "telegram.native")
        var effect: WhitegramVisualScrollEffect? = WhitegramVisualScrollEffect()
        func scroll(_ id: String, _ y: CGFloat, visible: Bool = true) {
            effect?.update(layer: layer, identity: id, rect: CGRect(x: 0, y: y, width: 200, height: 40), visible: visible)
        }
        scroll("a", 0)
        precondition(layer.animations.count == 1)
        scroll("a", 10)
        let animation = layer.animations["whitegram.visual.scroll"] as! CAAnimationGroup
        precondition(animation.animations?.count == 2)
        precondition((animation.animations![0] as! CABasicAnimation).isAdditive)
        precondition(layer.transform.x == -1 && layer.transform.y == -1, "Preserve Telegram's rotation/model transform")
        scroll("b", 12)
        precondition(layer.animations["whitegram.visual.scroll"] == nil, "Item change clears presentation animations")
        scroll("b", 20)
        precondition(layer.animations.count == 2)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        precondition(layer.animations.count == 1, "Background removes effect")
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        scroll("b", 30)
        precondition(layer.animations.count == 1, "Resume resets baseline")
        scroll("b", 40)
        precondition(layer.animations.count == 2)
        UIAccessibility.isReduceMotionEnabled = true
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        precondition(layer.animations.count == 1, "Reduce Motion updates live")
        scroll("b", 50)
        precondition(layer.animations.count == 1)
        UIAccessibility.isReduceMotionEnabled = false
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        scroll("b", 60)
        scroll("b", 70)
        WhitegramPreferences.set(["wgBubbleFisheyeEffect": true])
        precondition(layer.animations.count == 1, "Preference opt-out removes active animation")
        WhitegramPreferences.set(["chatScrollAnimation": true, "wgBubbleFisheyeEffect": true])
        scroll("b", 80)
        scroll("b", 90)
        scroll("b", 100, visible: false)
        precondition(layer.animations.count == 1, "Offscreen/context extraction cleanup")
        scroll("b", 110)
        scroll("b", 120)
        effect?.reset()
        precondition(layer.animations.count == 1, "Cell reuse cleanup")
        scroll("c", 0)
        scroll("c", 10)
        effect = nil
        precondition(layer.animations.count == 1, "Deinit removes only owned animations")

        let otherLayer = CALayer()
        var fisheye: WhitegramVisualFisheye? = WhitegramVisualFisheye()
        fisheye?.update(layers: [(layer, 0), (otherLayer, 76)], center: 0, enabled: true)
        precondition(layer.animations.count == 1)
        precondition(otherLayer.animations["whitegram.visual.fisheye"] != nil)
        fisheye?.update(layers: [(layer, 0)], center: 76, enabled: true)
        precondition(otherLayer.animations.isEmpty, "Removed tab cleanup")
        precondition(layer.animations["whitegram.visual.fisheye"] != nil)
        fisheye?.update(layers: [(layer, 0)], center: 76, enabled: false)
        precondition(layer.animations.count == 1, "Reordering/hidden tab row restores native presentation")
        fisheye?.update(layers: [(layer, 0)], center: 76, enabled: true)
        WhitegramPreferences.set([:])
        precondition(layer.animations.count == 1, "Live fisheye opt-out")
        WhitegramPreferences.set(["wgBubbleFisheyeEffect": true])
        precondition(layer.animations.count == 2, "Live fisheye enable uses the current geometry")
        fisheye = nil
        precondition(layer.animations.count == 1)
        print("Motion lifecycle: live preferences/accessibility/background, reuse, replacement, native animation preservation, deinit passed (UIKit test double)")
    }
}
