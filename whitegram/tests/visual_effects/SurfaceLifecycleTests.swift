import Foundation
import UIKit
import TelegramCore

@main
enum SurfaceLifecycleTests {
    static func main() {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIWindow(frame: frame)
        let native = UIView(frame: frame)
        host.addSubview(native)
        let avatar = UIView(frame: CGRect(x: 100, y: 80, width: 100, height: 100))
        native.addSubview(avatar)
        var profile: WhitegramVisualProfile? = WhitegramVisualProfile()
        func updateProfile(_ id: String = "a", hasPhoto: Bool = true, expanded: Bool = false, suppressed: Bool = false, colors: [UIColor] = []) {
            profile?.update(host: host, avatarView: avatar, frame: frame, identity: id, hasPhoto: hasPhoto,
                            colors: colors, base: .white, expanded: expanded, suppressed: suppressed)
        }
        WhitegramPreferences.set(["avatarBlurInProfile": true, "avatarGlow": true])
        updateProfile()
        precondition(host.subviews.count == 1, "No stale/placeholder background before image delivery")
        profile?.setImage(UIImage())
        let backdrop = host.subviews.first as! WhitegramVisualBackdrop
        precondition(backdrop.subviews.contains { $0 is UIVisualEffectView })
        precondition(native.layer.sublayers.count == 2, "Owned glow added below avatar")
        WhitegramPreferences.set(["avatarBlurInProfile": true, "avatarBlurReduced": true, "avatarBlurTint": true])
        precondition(!backdrop.subviews.contains { $0 is UIVisualEffectView }, "Reduced blur removes material")
        precondition(backdrop.subviews.last!.backgroundColor!.alpha == 0.35)
        precondition(native.layer.sublayers.count == 1, "Glow opt-out preserves avatar layer")
        updateProfile("b")
        precondition(host.subviews.count == 1, "Peer/photo replacement clears old background")
        profile?.setImage(UIImage())
        updateProfile("b", hasPhoto: false)
        precondition(host.subviews.count == 1, "Peer without an avatar clears cached image")
        WhitegramPreferences.set(["avatarBlurEffect": true])
        updateProfile("b")
        profile?.setImage(UIImage())
        precondition(host.subviews.count == 1, "Zoom-only effect is absent when collapsed")
        updateProfile("b", expanded: true)
        precondition(host.subviews.count == 2)
        updateProfile("b", expanded: true, suppressed: true)
        precondition(host.subviews.count == 1, "Editing/search suppression removes effects")
        WhitegramPreferences.set(["profileColorEffect": true])
        updateProfile("b", hasPhoto: false, colors: [.black, .white])
        precondition(host.subviews.count == 2, "Color works independently of avatar availability")
        profile = nil
        precondition(host.subviews.count == 1 && host.subviews[0] === native)

        var album: WhitegramVisualAlbumArt? = WhitegramVisualAlbumArt()
        album?.update(host: host, above: native.layer, frame: frame, base: .white)
        WhitegramPreferences.set(["albumArtBlur": true])
        precondition(host.subviews.count == 1)
        album?.setImage(UIImage())
        precondition(host.subviews.count == 2)
        UIAccessibility.isReduceTransparencyEnabled = true
        NotificationCenter.default.post(name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        precondition(host.subviews.count == 1, "Reduce Transparency tears down the blurred copy")
        UIAccessibility.isReduceTransparencyEnabled = false
        NotificationCenter.default.post(name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        precondition(host.subviews.count == 2, "Accessibility change reuses current cover")
        album?.setImage(nil)
        precondition(host.subviews.count == 1, "Track without artwork removes previous cover immediately")
        album?.setImage(UIImage())
        WhitegramPreferences.set([:])
        precondition(host.subviews.count == 1)
        WhitegramPreferences.set(["albumArtBlur": true])
        precondition(host.subviews.count == 2)
        album = nil
        precondition(host.subviews.count == 1)

        let screen = WhitegramVisualParticles(placement: .screen)
        let chat = WhitegramVisualParticles(placement: .chat)
        screen.frame = frame
        chat.frame = frame
        host.addSubview(screen)
        host.addSubview(chat)
        WhitegramPreferences.set(["particleEffect": 1, "particleMode": 0])
        precondition(screen.layer.sublayers.count == 1 && chat.layer.sublayers.isEmpty)
        precondition(!screen.isUserInteractionEnabled && screen.accessibilityElementsHidden)
        WhitegramPreferences.set(["particleEffect": 2, "particleMode": 1, "particleSpeed": 2, "particleDensity": 2])
        precondition(screen.layer.sublayers.isEmpty && chat.layer.sublayers.count == 1, "Mode migration cannot leave both emitters alive")
        let emitter = chat.layer.sublayers[0] as! CAEmitterLayer
        precondition(emitter.emitterCells![0].birthRate == 14)
        precondition(abs(emitter.emitterCells![0].velocity - 70.4) < 0.001)
        chat.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        chat.layoutSubviews()
        precondition(chat.layer.sublayers[0] === emitter && emitter.frame == chat.bounds, "Resize updates the existing emitter")
        chat.setVisible(false)
        precondition(chat.layer.sublayers.isEmpty && emitter.emitterCells == nil, "Offscreen tears down cells and layer")
        chat.setVisible(true)
        precondition(chat.layer.sublayers.count == 1)
        UIAccessibility.isReduceMotionEnabled = true
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        precondition(chat.layer.sublayers.isEmpty)
        UIAccessibility.isReduceMotionEnabled = false
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        TestPowerState.lowPower = true
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        precondition(chat.layer.sublayers.isEmpty)
        TestPowerState.lowPower = false
        NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        precondition(chat.layer.sublayers.count == 1)
        chat.removeFromSuperview()
        precondition(chat.layer.sublayers.isEmpty, "Window detachment tears down the emitter")
        WhitegramPreferences.set([:])
        precondition(screen.layer.sublayers.isEmpty)
        print("Surface lifecycle: live profile/album blur, photo/track reset, glow, tint, editing/accessibility gates, particle mode/resize/offscreen/power teardown passed (UIKit test double)")
    }
}
