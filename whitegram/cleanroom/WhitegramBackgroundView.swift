import Foundation
import UIKit
import AVFoundation
import TelegramCore

public final class WhitegramBackgroundView: UIView {
    public enum Surface { case chat, profile }
    private let accountId: Int64
    private let surface: Surface
    private let imageView = UIImageView()
    private let wash = UIView()
    private let videoLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var selectedFile: String?
    private var generation = 0
    private var ownProfile = false
    private var contentAllowed = true
    private var visible = false
    private var configured = false

    public init(accountId: Int64, surface: Surface) {
        self.accountId = accountId
        self.surface = surface
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false
        self.accessibilityElementsHidden = true
        self.clipsToBounds = true
        self.imageView.contentMode = .scaleAspectFill
        self.addSubview(self.imageView)
        self.layer.addSublayer(self.videoLayer)
        self.videoLayer.videoGravity = .resizeAspectFill
        self.addSubview(self.wash)
        self.isHidden = true
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification, UIAccessibility.reduceMotionStatusDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if note.name == UIApplication.willResignActiveNotification { self?.player?.pause() }
                else { self?.updatePlayback() }
            })
        }
    }

    required public init?(coder: NSCoder) { return nil }

    deinit {
        self.player?.pause()
        self.looper?.disableLooping()
        self.player?.removeAllItems()
        self.statusObservation?.invalidate()
        for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
    }

    public func configure(isOwnProfile: Bool = false, contentAllowed: Bool = true, tint: UIColor) {
        let needsReload = !self.configured || self.ownProfile != isOwnProfile || self.contentAllowed != contentAllowed
        self.configured = true
        self.ownProfile = isOwnProfile
        self.contentAllowed = contentAllowed
        self.wash.backgroundColor = tint.withAlphaComponent(self.surface == .profile ? 0.62 : 0.25)
        if needsReload { self.reload() }
    }

    public func setVisible(_ visible: Bool) {
        self.visible = visible
        self.updatePlayback()
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        self.updatePlayback()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds
        self.wash.frame = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.videoLayer.frame = self.bounds
        CATransaction.commit()
    }

    private func stop() {
        self.generation += 1
        self.player?.pause()
        self.statusObservation?.invalidate()
        self.statusObservation = nil
        self.looper?.disableLooping()
        self.looper = nil
        self.player?.removeAllItems()
        self.player = nil
        self.videoLayer.player = nil
        self.imageView.image = nil
        self.isHidden = true
    }

    private func reload() {
        let selection: (String, WhitegramBackgroundKind)?
        do {
            let policy = WhitegramBackgroundPolicy(values: try WhitegramNavigationSettings.values(accountId: self.accountId))
            if !self.contentAllowed { selection = nil }
            else if self.surface == .chat { selection = policy.video.map { ($0, .video) } }
            else { selection = policy.profileFile(isOwnProfile: self.ownProfile) }
        } catch {
            self.selectedFile = nil
            self.stop()
            NSLog("Whitegram: background settings could not be read: %@", error.localizedDescription)
            return
        }
        guard selection?.0 != self.selectedFile else { return }
        self.stop()
        self.selectedFile = selection?.0
        guard let (file, kind) = selection else { return }
        let generation = self.generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let url = try WhitegramBackgroundStore.url(file: file, kind: kind)
                let image = kind == .cover ? UIImage(contentsOfFile: url.path) : nil
                if kind == .cover && image == nil { throw WhitegramBackgroundStore.invalidFile() }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    if let image {
                        self.imageView.image = image
                        self.isHidden = false
                    } else {
                        self.startVideo(url: url, generation: generation)
                    }
                }
            } catch {
                NSLog("Whitegram: local background could not be loaded: %@", error.localizedDescription)
            }
        }
    }

    private func startVideo(url: URL, generation: Int) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0.0
        self.player = player
        self.videoLayer.player = player
        self.looper = AVPlayerLooper(player: player, templateItem: item)
        // The looper inserts copies of the template; observe the actual queued item.
        self.statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                if item.status == .readyToPlay {
                    self.isHidden = false
                    self.updatePlayback()
                } else if item.status == .failed {
                    NSLog("Whitegram: local video playback failed: %@", item.error?.localizedDescription ?? "Unknown media error")
                    self.stop()
                }
            }
        }
        self.updatePlayback()
    }

    private func updatePlayback() {
        let play = WhitegramBackgroundPolicy.shouldPlay(visible: self.visible && self.contentAllowed, attached: self.window != nil,
            active: UIApplication.shared.applicationState == .active, reduceMotion: UIAccessibility.isReduceMotionEnabled,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if play { self.player?.play() } else { self.player?.pause() }
    }
}
