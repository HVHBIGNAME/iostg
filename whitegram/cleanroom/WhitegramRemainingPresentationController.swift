import Foundation
import UIKit
import AccountContext
import Display
import ItemListUI
import PresentationDataUtils
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct WhitegramRemainingPresentationEntry: ItemListNodeEntry {
    enum Content: Equatable {
        case badge(String, String, Bool)
        case text(String)
        case link(String)
    }
    let stableId: String
    let order: Int
    let content: Content
    var section: ItemListSectionId { return 0 }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.order < rhs.order }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! WhitegramRemainingPresentationActions
        switch content {
        case let .badge(name, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass,
                icon: whitegramRemainingAppBadgeImage(name), iconSize: CGSize(width: 88, height: 22), title: title,
                style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: section,
                action: { actions.selectBadge(name) })
        case let .text(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .link(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title,
                kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: { actions.openBuilder() })
        }
    }
}

private final class WhitegramRemainingPresentationActions {
    let context: AccountContext
    weak var controller: ViewController?
    init(context: AccountContext) { self.context = context }
    func selectBadge(_ name: String) {
        guard whitegramRemainingAppBadgeImage(name) != nil else { return }
        if !WhitegramPreferences.set(name, for: "appBadgeName") {
            let alert = UIAlertController(title: "Whitegram", message: "Could not save badge selection.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            controller?.present(alert, animated: true)
        }
    }
    func openBuilder() {
        context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: WhitegramRemainingInformation.iconPackSite,
            forceExternal: false, presentationData: context.sharedContext.currentPresentationData.with { $0 },
            navigationController: controller?.navigationController as? NavigationController, dismissInput: {})
    }
}

public func whitegramRemainingPresentationController(context: AccountContext, id: String) -> ViewController {
    let actions = WhitegramRemainingPresentationActions(context: context)
    let updates = Signal<Bool, NoError> { subscriber in
        let names = [WhitegramPreferences.updatedNotification, WhitegramLocalizationStore.changedNotification]
        let observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in subscriber.putNext(true) }
        }
        subscriber.putNext(true)
        return ActionDisposable { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
    let signal = combineLatest(context.sharedContext.presentationData, updates)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        func text(_ key: String) -> String { WhitegramLocalization.string(key, baseLanguage: data.strings.baseLanguageCode) }
        var entries: [WhitegramRemainingPresentationEntry] = []
        func add(_ key: String, _ content: WhitegramRemainingPresentationEntry.Content) {
            entries.append(WhitegramRemainingPresentationEntry(stableId: key, order: entries.count, content: content))
        }
        let title: String
        if id == "appBadgeColorIsBlack" {
            title = text("s.appBadgeColor")
            let selected = WhitegramRemainingPresentationPolicy.appBadgeName(WhitegramPreferences.string("appBadgeName"))
            for name in ["WGBadgePrimary", "WGBadgeWhite", "WGBadgeBlack"] where whitegramRemainingAppBadgeImage(name) != nil {
                let label = name == "WGBadgePrimary" ? "Whitegram" : text(name == "WGBadgeWhite" ? "appIcon.badgeWhite" : "appIcon.badgeBlack")
                add(name, .badge(name, label, selected == name))
            }
            add("help", .text(text("wh.appBadgeColor")))
            add("availability", .text("Only recovered badge images installed in this build are listed. The badge uses the app's existing portrait/Dynamic Island visibility rules."))
            if whitegramRemainingAppBadgeImage(selected) == nil {
                add("missing", .text("The saved badge image is unavailable in this build: " + selected))
            }
        } else {
            title = text("s.createIconPack")
            add("description", .text(text(WhitegramRemainingInformation.iconPackSiteDescriptionKey)))
            add("site", .link(WhitegramRemainingInformation.iconPackSite))
            add("info", .text(text("icons.info")))
        }
        let presentation = ItemListPresentationData(data)
        return (ItemListControllerState(presentationData: presentation, title: .text(title), leftNavigationButton: nil,
            rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back), animateChanges: false),
            (ItemListNodeState(presentationData: presentation, entries: entries, style: .blocks, animateChanges: false), actions))
    }
    let controller = ItemListController(context: context, state: signal)
    actions.controller = controller
    return controller
}
