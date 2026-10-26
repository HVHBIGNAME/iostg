import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import PresentationDataUtils
import AccountContext
import TabBarUI

/// The real chat-list controller in upstream preview mode; no history preload owner.
public func whitegramChatListPreviewController(context: AccountContext) -> ViewController {
    return context.sharedContext.makeChatListController(context: context, location: .chatList(groupId: .root),
        controlsHistoryPreload: false, hideNetworkActivityStatus: false, previewing: true, enableDebugActions: false)
}

/// Uses the production TabBarController/TabBarComponent with explicitly labelled sample pages.
public final class WhitegramNavigationPreviewController: TabBarControllerImpl {
    private let context: AccountContext
    private var observer: NSObjectProtocol?
    private var presentationDisposable: Disposable?
    private var pages: [String: WhitegramNavigationPreviewPage] = [:]

    public init(context: AccountContext) {
        self.context = context
        super.init(presentationData: context.sharedContext.currentPresentationData.with { $0 })
        self.title = "Tab bar preview"
        self.observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        self.presentationDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] data in
            self?.updatePresentationData(data)
            self?.refresh()
        })
        self.whitegramRestoreTabBar = { [weak self] in
            // A preview-local escape; previewing must never change saved settings.
            self?.whitegramPersistentTabBarHidden = false
        }
        self.refresh()
    }

    required public init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        self.presentationDisposable?.dispose()
    }

    private func refresh() {
        do {
            let values = try WhitegramNavigationSettings.values(accountId: self.context.account.id.int64)
            let policy = WhitegramNavigationPolicy(values: values)
            let data = self.context.sharedContext.currentPresentationData.with { $0 }
            var tabs = WhiteGramTabSettings.current
            tabs.hideContactsTab = WhitegramNavigationPolicy.flag(values["hideContactsTab"])
            tabs.hideCallsTab = WhitegramNavigationPolicy.flag(values["hideCallsTab"])
            tabs.hideTabTitles = WhitegramNavigationPolicy.flag(values["hideTabLabels"])
            self.whiteGramTabSettings = tabs
            var items: [(String, String)] = []
            if tabs.compactPanel || !tabs.hideContactsTab { items.append((data.strings.Contacts_Title, "person.2")) }
            if tabs.compactPanel || !tabs.hideCallsTab { items.append((data.strings.Calls_TabTitle, "phone")) }
            items.append((data.strings.DialogList_Title, "bubble.left.and.bubble.right"))
            items.append((data.strings.Settings_Title, "gearshape"))
            if policy.separateProfileTab { items.append(("Profile", "person.crop.circle")) }
            let controllers: [ViewController] = items.map { title, symbol in
                let page = self.pages[symbol] ?? WhitegramNavigationPreviewPage(title: title, symbol: symbol, data: data)
                self.pages[symbol] = page
                page.update(title: title, data: data)
                page.navigationItem.leftBarButtonItem = UIBarButtonItem(title: data.strings.Common_Back, style: .plain, target: self, action: #selector(self.closePreview))
                return page
            }
            let previous = self.currentController
            let selected = controllers.firstIndex(where: { $0 === previous }) ?? max(0, controllers.count - (policy.separateProfileTab ? 3 : 2))
            self.whitegramPersistentTabBarHidden = policy.hideBottomTabBar
            self.setControllers(controllers, selectedIndex: selected)
            self.updateLayout(transition: .immediate)
        } catch { NSLog("Whitegram: preview settings could not be read: %@", error.localizedDescription) }
    }

    @objc private func closePreview() { self.navigationController?.popViewController(animated: true) }
}

private final class WhitegramNavigationPreviewPage: ViewController {
    private let label = UILabel()
    private var data: PresentationData

    init(title: String, symbol: String, data: PresentationData) {
        self.data = data
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: data))
        self.title = title
        self.tabBarItem.title = title
        self.tabBarItem.image = UIImage(systemName: symbol)
        self.tabBarItem.selectedImage = UIImage(systemName: symbol)
        self.ready.set(.single(true))
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.label.numberOfLines = 0
        self.label.textAlignment = .center
        self.label.font = UIFont.preferredFont(forTextStyle: .body)
        self.label.adjustsFontForContentSizeCategory = true
        self.displayNode.view.addSubview(self.label)
        self.update(title: self.title ?? "", data: self.data)
        self.displayNodeDidLoad()
    }

    func update(title: String, data: PresentationData) {
        self.data = data
        self.title = title
        self.tabBarItem.title = title
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: data), transition: .immediate)
        if self.isNodeLoaded {
            self.displayNode.backgroundColor = data.theme.list.blocksBackgroundColor
            self.label.textColor = data.theme.list.itemPrimaryTextColor
            self.label.text = "\(title)\n\nSample page for the live tab bar preview.\nUse the tabs to inspect selection and layout."
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.label.frame = CGRect(x: 24, y: self.navigationLayout(layout: layout).navigationFrame.maxY + 72,
            width: max(0, layout.size.width - 48), height: max(0, layout.size.height - layout.intrinsicInsets.bottom - 220))
    }
}
