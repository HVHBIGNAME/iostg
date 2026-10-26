import Foundation

@main
enum PolicyTests {
    static func near(_ value: Double, _ expected: Double) {
        precondition(abs(value - expected) < 0.000001, "\(value) != \(expected)")
    }

    static func main() {
        let defaults = WhitegramVisualPolicy(values: [:])
        precondition(!defaults.avatarBlurEffect && !defaults.avatarBlurInProfile && !defaults.avatarBlurTint)
        precondition(!defaults.avatarBlurReduced && !defaults.avatarGlow && !defaults.profileColorEffect)
        precondition(!defaults.albumArtBlur && !defaults.chatScrollAnimation && !defaults.fisheye)
        precondition(defaults.particle == .off && defaults.placement == .screen)
        near(defaults.speedMultiplier, 1)
        near(defaults.densityMultiplier, 1)
        for invalid: Any in [true, "1", -1, 3, 1.25, Double.nan, Double.infinity, NSNull()] {
            let value = WhitegramVisualPolicy(values: ["particleSpeed": invalid, "particleDensity": invalid, "particleEffect": invalid])
            precondition(value.particleSpeed == 1 && value.particleDensity == 1 && value.particle == .off)
        }
        for invalid: Any in [1, "true", "false", 0.0, NSNull()] {
            precondition(!WhitegramVisualPolicy(values: ["avatarBlurInProfile": invalid]).avatarBlurInProfile)
        }
        for speed in 0 ... 2 {
            let value = WhitegramVisualPolicy(values: ["particleSpeed": speed, "particleDensity": speed])
            near(value.speedMultiplier, [0.45, 1, 2.2][speed])
            near(value.densityMultiplier, [0.45, 1, 2][speed])
        }
        let profile = WhitegramVisualPolicy(values: ["avatarBlurInProfile": true])
        precondition(profile.showsAvatarBackground(expanded: false, hasImage: true, suppressed: false))
        precondition(!profile.showsAvatarBackground(expanded: true, hasImage: false, suppressed: false))
        precondition(!profile.showsAvatarBackground(expanded: true, hasImage: true, suppressed: true))
        let zoom = WhitegramVisualPolicy(values: ["avatarBlurEffect": true])
        precondition(!zoom.showsAvatarBackground(expanded: false, hasImage: true, suppressed: false))
        precondition(zoom.showsAvatarBackground(expanded: true, hasImage: true, suppressed: false))
        for effect in 1 ... 2 {
            for mode in 0 ... 1 {
                let particles = WhitegramVisualPolicy(values: ["particleEffect": effect, "particleMode": mode])
                let placement = WhitegramVisualPolicy.Placement(rawValue: mode)!
                precondition(particles.showsParticles(in: placement, visible: true, active: true, reduceMotion: false, lowPower: false))
                for flags in [[false, true, false, false], [true, false, false, false], [true, true, true, false], [true, true, false, true]] {
                    precondition(!particles.showsParticles(in: placement, visible: flags[0], active: flags[1], reduceMotion: flags[2], lowPower: flags[3]))
                }
                precondition(!particles.showsParticles(in: mode == 0 ? .chat : .screen, visible: true, active: true, reduceMotion: false, lowPower: false))
            }
        }
        near(WhitegramVisualPolicy.fisheyeScale(distance: 0, enabled: true, reduceMotion: false), 1)
        near(WhitegramVisualPolicy.fisheyeScale(distance: 76, enabled: true, reduceMotion: false), 0.8)
        near(WhitegramVisualPolicy.fisheyeScale(distance: -76, enabled: true, reduceMotion: false), 0.8)
        near(WhitegramVisualPolicy.fisheyeScale(distance: 1000, enabled: true, reduceMotion: false), 0.45)
        near(WhitegramVisualPolicy.fisheyeScale(distance: 76, enabled: true, reduceMotion: true), 1)
        near(WhitegramVisualPolicy.fisheyeScale(distance: .nan, enabled: true, reduceMotion: false), 1)
        near(WhitegramVisualPolicy.scrollDisplacement(offset: 10), -8.2)
        near(WhitegramVisualPolicy.scrollDisplacement(offset: -100), 24)
        near(WhitegramVisualPolicy.scrollDisplacement(offset: .infinity), 0)
        near(WhitegramVisualPolicy.scrollScale(displacement: 24), 0.978)
        var scroll = WhitegramVisualScrollState()
        precondition(scroll.update(identity: "a", position: 0, size: 40, enabled: true) == nil)
        near(scroll.update(identity: "a", position: 10, size: 40, enabled: true)!, -8.2)
        precondition(scroll.update(identity: "b", position: 12, size: 40, enabled: true) == nil, "New item must not inherit previous offset")
        precondition(scroll.update(identity: "b", position: 20, size: 80, enabled: true) == nil, "Layout resize is not scrolling")
        precondition(scroll.update(identity: "b", position: 500, size: 80, enabled: true) == nil, "Programmatic jumps do not animate")
        precondition(scroll.update(identity: "b", position: 505, size: 80, enabled: false) == nil)
        precondition(scroll.update(identity: "b", position: 510, size: 80, enabled: true) == nil, "Enable establishes a new baseline")
        scroll.reset()
        precondition(scroll.update(identity: "b", position: 512, size: 80, enabled: true) == nil, "Reuse resets position")
        precondition(scroll.update(identity: "b", position: .nan, size: 80, enabled: true) == nil)
        print("Visual policies: defaults, malformed values, particle gates, recovered formulas, resize/jump/reuse transitions passed")
    }
}
