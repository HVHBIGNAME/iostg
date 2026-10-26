import Foundation
import CoreFoundation

public struct WhitegramVisualPolicy: Equatable {
    public enum Particle: Int { case off = 0, snow = 1, autumn = 2 }
    public enum Placement: Int { case screen = 0, chat = 1 }

    public let avatarBlurEffect: Bool
    public let avatarBlurInProfile: Bool
    public let avatarBlurReduced: Bool
    public let avatarBlurTint: Bool
    public let avatarGlow: Bool
    public let profileColorEffect: Bool
    public let albumArtBlur: Bool
    public let chatScrollAnimation: Bool
    public let fisheye: Bool
    public let particle: Particle
    public let placement: Placement
    public let particleSpeed: Int
    public let particleDensity: Int

    public init(values: [String: Any], legacyDefaults: UserDefaults? = nil) {
        func value(_ key: String, legacy: String? = nil) -> Any? {
            return values[key] ?? legacyDefaults?.object(forKey: legacy ?? "wg_" + key)
        }
        func flag(_ key: String, legacy: String? = nil) -> Bool {
            guard let number = value(key, legacy: legacy) as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            return number.boolValue
        }
        func choice(_ key: String, default fallback: Int, range: ClosedRange<Int>) -> Int {
            guard let number = value(key) as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return fallback }
            let raw = number.doubleValue
            guard raw.isFinite, raw.rounded() == raw, raw >= Double(range.lowerBound), raw <= Double(range.upperBound) else { return fallback }
            return Int(raw)
        }
        avatarBlurEffect = flag("avatarBlurEffect", legacy: "wg_avatarBlurEffectEnabled")
        avatarBlurInProfile = flag("avatarBlurInProfile")
        avatarBlurReduced = flag("avatarBlurReduced")
        avatarBlurTint = flag("avatarBlurTint", legacy: "wg_avatarBlurTintEnabled")
        avatarGlow = flag("avatarGlow", legacy: "wg_avatarGlowEnabled")
        profileColorEffect = flag("profileColorEffect", legacy: "wg_profileColorEffectEnabled")
        albumArtBlur = flag("albumArtBlur", legacy: "wg_albumArtBlurEnabled")
        chatScrollAnimation = flag("chatScrollAnimation")
        fisheye = flag("wgBubbleFisheyeEffect", legacy: "wg_bubbleFisheyeEffect")
        particle = Particle(rawValue: choice("particleEffect", default: 0, range: 0 ... 2)) ?? .off
        placement = Placement(rawValue: choice("particleMode", default: 0, range: 0 ... 1)) ?? .screen
        particleSpeed = choice("particleSpeed", default: 1, range: 0 ... 2)
        particleDensity = choice("particleDensity", default: 1, range: 0 ... 2)
    }

    public var speedMultiplier: Double { return [0.45, 1.0, 2.2][particleSpeed] }
    public var densityMultiplier: Double { return [0.45, 1.0, 2.0][particleDensity] }

    public func showsAvatarBackground(expanded: Bool, hasImage: Bool, suppressed: Bool) -> Bool {
        return !suppressed && hasImage && (avatarBlurInProfile || (avatarBlurEffect && expanded))
    }

    public func showsParticles(in placement: Placement, visible: Bool, active: Bool, reduceMotion: Bool, lowPower: Bool) -> Bool {
        return particle != .off && self.placement == placement && visible && active && !reduceMotion && !lowPower
    }

    // ARM64 0x83f2f4...0x83f304: max(0.45, 1 - abs(distance) / 76 * 0.2).
    public static func fisheyeScale(distance: Double, enabled: Bool, reduceMotion: Bool) -> Double {
        guard enabled, !reduceMotion, distance.isFinite else { return 1.0 }
        return max(0.45, 1.0 - abs(distance) / 76.0 * 0.2)
    }

    public static func scrollDisplacement(offset: Double) -> Double {
        guard offset.isFinite else { return 0.0 }
        return max(-20.0, min(20.0, offset * -0.66)) + max(-4.0, min(4.0, offset * -0.16))
    }

    public static func scrollScale(displacement: Double) -> Double {
        guard displacement.isFinite else { return 1.0 }
        return 1.0 - min(0.022, abs(displacement) * 0.0011)
    }
}

/// Prevents scrolling animations from carrying a previous cell's position into its next item.
public struct WhitegramVisualScrollState {
    private var identity: String?
    private var position: Double?
    private var size: Double?

    public init() {}

    public mutating func reset() {
        identity = nil
        position = nil
        size = nil
    }

    public mutating func update(identity: String, position: Double, size: Double, enabled: Bool) -> Double? {
        guard enabled, position.isFinite, size.isFinite, size > 0.0 else {
            reset()
            return nil
        }
        defer {
            self.identity = identity
            self.position = position
            self.size = size
        }
        guard self.identity == identity, self.size == size, let previous = self.position else { return nil }
        let delta = position - previous
        guard abs(delta) > 0.01, abs(delta) < 120.0 else { return nil }
        return WhitegramVisualPolicy.scrollDisplacement(offset: delta)
    }
}
