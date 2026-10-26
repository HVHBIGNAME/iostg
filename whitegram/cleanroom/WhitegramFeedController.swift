import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import ChatControllerInteraction

public final class WhitegramFeedController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let loader: WhitegramFeedLoader
    private let table = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let footer = UIButton(type: .system)
    private var data: PresentationData
    private var presentationDisposable: Disposable?
    private var mediaDisposable: Disposable?
    private var loaded = false
    private var visible = false
    private var renderedCount = 0
    private var openGeneration = 0
    private var observers: [NSObjectProtocol] = []
    weak var rootNavigation: NavigationController?

    public init(context: AccountContext) {
        self.context = context
        self.loader = WhitegramFeedLoader(context: context)
        self.data = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.data))
        self.title = "Posts"
        self.tabBarItem.title = "Posts"
        self.tabBarItem.image = UIImage(systemName: "rectangle.stack")
        self.tabBarItem.selectedImage = UIImage(systemName: "rectangle.stack.fill")
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(self.refresh))
        self.ready.set(.single(true))
        self.loader.updated = { [weak self] _ in self?.updateView() }
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let self else { return }
            self.data = data
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: data), transition: .immediate)
            self.updateView(forceReload: true)
        })
        self.observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.loader.suspend()
        })
        self.observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.visible else { return }
            self.loader.resume()
        })
    }

    required public init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        self.presentationDisposable?.dispose()
        self.mediaDisposable?.dispose()
        self.observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.table.dataSource = self
        self.table.delegate = self
        self.table.estimatedRowHeight = 180
        self.table.rowHeight = UITableView.automaticDimension
        self.table.register(WhitegramFeedCell.self, forCellReuseIdentifier: "post")
        self.refreshControl.addTarget(self, action: #selector(self.refresh), for: .valueChanged)
        self.table.refreshControl = self.refreshControl
        self.footer.titleLabel?.numberOfLines = 0
        self.footer.titleLabel?.textAlignment = .center
        self.footer.addTarget(self, action: #selector(self.more), for: .touchUpInside)
        self.footer.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
        self.table.tableFooterView = self.footer
        self.displayNode.view.addSubview(self.table)
        self.updateView()
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.table.frame = CGRect(origin: .zero, size: layout.size)
        self.table.contentInset = UIEdgeInsets(top: self.navigationLayout(layout: layout).navigationFrame.maxY,
            left: layout.safeInsets.left, bottom: layout.intrinsicInsets.bottom, right: layout.safeInsets.right)
        self.table.scrollIndicatorInsets = self.table.contentInset
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.visible = true
        self.openGeneration += 1
        self.mediaDisposable?.dispose()
        self.mediaDisposable = nil
        if !self.loaded { self.loaded = true; self.loader.refresh() } else { self.loader.resume() }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.visible = false
        self.loader.suspend()
    }

    @objc private func refresh() { self.loader.refresh() }
    @objc private func more() { self.loader.loadMore() }

    private func updateView(forceReload: Bool = false) {
        guard self.isNodeLoaded else { return }
        self.table.backgroundColor = self.data.theme.list.plainBackgroundColor
        self.table.separatorColor = self.data.theme.list.itemPlainSeparatorColor
        let state = self.loader.state
        let previousCount = self.renderedCount
        self.renderedCount = state.posts.count
        if forceReload || self.renderedCount < previousCount {
            self.table.reloadData()
        } else if self.renderedCount > previousCount {
            self.table.insertRows(at: (previousCount..<self.renderedCount).map { IndexPath(row: $0, section: 0) }, with: .none)
        }
        let text: String
        if let error = state.error { text = error + "\nTap to retry" }
        else if state.loading { text = "Loading posts from \(state.channels) synced channels…" }
        else if state.ended { text = state.posts.isEmpty ? "No posts in your synced subscribed channels. Pull to refresh." : "End of channel histories" }
        else { text = "Load older posts" }
        self.footer.setTitle(text, for: .normal)
        self.footer.isEnabled = !state.loading && !state.ended
        if !state.loading { self.refreshControl.endRefreshing() }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return self.loader.state.posts.count }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "post", for: indexPath) as! WhitegramFeedCell
        let message = self.loader.state.posts[indexPath.row]
        cell.update(message: message, theme: self.data.theme)
        cell.openMedia = { [weak self] in self?.open(message: message, media: true) }
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.open(message: self.loader.state.posts[indexPath.row], media: false)
    }

    private func open(message: Message, media: Bool) {
        guard let navigation = self.rootNavigation ?? self.navigationController as? NavigationController,
              let peer = message.peers[message.id.peerId] else { return }
        self.openGeneration += 1
        let generation = self.openGeneration
        self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigation,
            context: self.context, chatLocation: .peer(EnginePeer(peer)),
            subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false),
            keepStack: .always, completion: { [weak self] controller in
                guard let self, self.openGeneration == generation, media, let chat = controller as? ChatControllerImpl else { return }
                self.mediaDisposable?.dispose()
                self.mediaDisposable = (chat.ready.get() |> filter { $0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak self, weak chat] _ in
                    guard let self, self.openGeneration == generation, let chat else { return }
                    if chat.controllerInteraction?.openMessage(message, OpenMessageParams(mode: .default)) != true {
                        let alert = UIAlertController(title: "Open media", message: "This attachment is available from the original post below.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        chat.present(alert, animated: true)
                    }
                })
            }))
    }
}

private final class WhitegramFeedCell: UITableViewCell {
    private let heading = UILabel()
    private let body = UILabel()
    private let mediaLabel = UILabel()
    private let mediaButton = UIButton(type: .system)
    var openMedia: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        heading.font = UIFont.preferredFont(forTextStyle: .headline)
        body.font = UIFont.preferredFont(forTextStyle: .body)
        mediaLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        for label in [heading, body, mediaLabel] { label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true }
        mediaButton.setTitle("Open media", for: .normal)
        mediaButton.addTarget(self, action: #selector(self.mediaPressed), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [heading, body, mediaLabel, mediaButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)])
    }

    required init?(coder: NSCoder) { return nil }
    @objc private func mediaPressed() { self.openMedia?() }

    func update(message: Message, theme: PresentationTheme) {
        let name = (message.peers[message.id.peerId] as? TelegramChannel)?.title ?? "Channel"
        let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(message.timestamp)), dateStyle: .medium, timeStyle: .short)
        heading.text = name + " · " + date
        body.text = message.text
        body.isHidden = message.text.isEmpty
        let media = message.media.compactMap { media -> String? in
            if media is TelegramMediaImage { return "Photo" }
            if let file = media as? TelegramMediaFile { return file.fileName ?? (file.isVideo ? "Video" : "Attachment") }
            if media is TelegramMediaPoll { return "Poll — open original to vote" }
            return "Attachment — open original"
        }
        mediaLabel.text = media.joined(separator: " · ")
        mediaLabel.isHidden = media.isEmpty
        mediaButton.isHidden = !message.media.contains { $0 is TelegramMediaImage || $0 is TelegramMediaFile }
        backgroundColor = theme.list.itemBlocksBackgroundColor
        heading.textColor = theme.list.itemAccentColor
        body.textColor = theme.list.itemPrimaryTextColor
        mediaLabel.textColor = theme.list.itemSecondaryTextColor
        accessibilityHint = "Open original channel post"
    }
}
