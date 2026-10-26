import Foundation
import UIKit
import AVFoundation
import ImageIO
import Display
import AsyncDisplayKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext

public final class WhitegramBackgroundController: ViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let context: AccountContext
    private let kind: WhitegramBackgroundKind
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var observer: NSObjectProtocol?
    private var pickerScope: WhitegramPreferences.Scope?
    private var importing = false

    public init(context: AccountContext, kind: WhitegramBackgroundKind) {
        self.context = context
        self.kind = kind
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }))
        self.title = kind == .cover ? "Local profile cover" : "Local video background"
        self.observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in self?.table.reloadData() }
    }

    required public init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.context.sharedContext.currentPresentationData.with { $0.theme.list.blocksBackgroundColor }
        self.table.dataSource = self
        self.table.delegate = self
        self.displayNode.view.addSubview(self.table)
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.table.frame = CGRect(origin: .zero, size: layout.size)
        self.table.contentInset.top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.table.contentInset.bottom = layout.intrinsicInsets.bottom
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return self.kind == .video ? 3 : 2 }
    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return self.kind == .cover
            ? "A still image for your own profile on this installation. Choose from Files, up to 8 MB. Reset restores the Telegram cover."
            : "A muted, looping chat wallpaper, up to 40 MB and 60 seconds. Playback pauses offscreen, in the background, in Low Power Mode and with Reduce Motion. Optionally use it on your own profile; it takes precedence over the still cover."
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.row == 0 {
            cell.textLabel?.text = self.importing ? "Importing…" : "Choose from Files"
            cell.accessoryType = .disclosureIndicator
        } else if indexPath.row == 1 {
            cell.textLabel?.text = "Reset background"
            cell.textLabel?.textColor = .systemRed
        } else {
            cell.textLabel?.text = "Also use on my profile"
            let toggle = UISwitch()
            do {
                toggle.isOn = WhitegramBackgroundPolicy(values: try WhitegramNavigationSettings.values(accountId: self.context.account.id.int64)).videoInProfile
            } catch {
                toggle.isEnabled = false
                cell.detailTextLabel?.text = "Settings unavailable"
                NSLog("Whitegram: background settings could not be read: %@", error.localizedDescription)
            }
            toggle.addTarget(self, action: #selector(self.profileToggled(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        }
        cell.isUserInteractionEnabled = !self.importing
        return cell
    }

    @objc private func profileToggled(_ toggle: UISwitch) {
        do { try WhitegramNavigationSettings.update(["videoBackgroundInProfile": toggle.isOn], accountId: self.context.account.id.int64) }
        catch { toggle.isOn.toggle(); self.showError(error) }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !self.importing else { return }
        do {
            if indexPath.row == 1 {
                try WhitegramBackgroundStore.reset(self.kind, accountId: self.context.account.id.int64)
            } else if indexPath.row == 0 {
                self.pickerScope = try WhitegramPreferences.scope(accountId: self.context.account.id.int64)
                let picker = UIDocumentPickerViewController(documentTypes: [self.kind == .cover ? "public.image" : "public.movie"], in: .import)
                picker.allowsMultipleSelection = false
                picker.delegate = self
                self.presentUIKit(picker)
            }
        } catch { self.showError(error) }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { self.pickerScope = nil }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let scope = self.pickerScope, !self.importing else { return }
        self.pickerScope = nil
        self.importing = true
        self.table.reloadData()
        let kind = self.kind
        let accountId = self.context.account.id.int64
        // Keep the imported URL's access until AVFoundation has finished inspecting it.
        let access = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Self.prepare(url: url, kind: kind) { result in
                if access { url.stopAccessingSecurityScopedResource() }
                guard self != nil else { return }
                let saved = result.flatMap { data -> Result<Void, Error> in
                    Result { try WhitegramBackgroundStore.save(data, kind: kind, accountId: accountId, expectedScope: scope) }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer { self.importing = false; self.table.reloadData() }
                    if case let .failure(error) = saved { self.showError(error) }
                }
            }
        }
    }

    private static func prepare(url: URL, kind: WhitegramBackgroundKind, completion: @escaping (Result<Data, Error>) -> Void) {
        do {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let size = info.fileSize, size > 0, size <= kind.maximumBytes else { throw WhitegramBackgroundStore.invalidFile() }
            let data = try Data(contentsOf: url)
            guard data.count <= kind.maximumBytes else { throw WhitegramBackgroundStore.invalidFile() }
            if kind == .cover {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary),
                      let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.88) else { throw WhitegramBackgroundStore.invalidFile() }
                completion(.success(jpeg))
            } else {
                let asset = AVURLAsset(url: url)
                let keys = ["playable", "duration", "tracks", "hasProtectedContent"]
                asset.loadValuesAsynchronously(forKeys: keys) {
                    for key in keys {
                        var error: NSError?
                        guard asset.statusOfValue(forKey: key, error: &error) == .loaded else {
                            completion(.failure(error ?? WhitegramBackgroundStore.invalidFile())); return
                        }
                    }
                    let duration = CMTimeGetSeconds(asset.duration)
                    guard asset.isPlayable, !asset.hasProtectedContent, duration.isFinite, duration > 0, duration <= 60,
                          !asset.tracks(withMediaType: .video).isEmpty else { completion(.failure(WhitegramBackgroundStore.invalidFile())); return }
                    completion(.success(data))
                }
            }
        } catch { completion(.failure(error)) }
    }

    private func presentUIKit(_ controller: UIViewController) {
        guard var presenter = self.viewIfLoaded?.window?.rootViewController else { return }
        while let current = presenter.presentedViewController { presenter = current }
        presenter.present(controller, animated: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Could not update background", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.presentUIKit(alert)
    }
}
