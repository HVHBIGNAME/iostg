import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import AccountContext

private final class WhitegramAccountSettingsCoordinator {
    let context: AccountContext
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    private var number = 0
    private var observers: [NSObjectProtocol] = []
    var error: String?

    init(context: AccountContext) {
        self.context = context
        for name in [WhitegramPreferences.updatedNotification, WhitegramLocalizationStore.changedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.changed() })
        }
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    func changed() { number += 1; revision.set(number) }

    func useShared(_ shared: Bool, accountId: Int64) {
        do {
            try WhitegramPreferences.setUsesSeparateSettings(!shared, accountId: accountId)
            error = nil
        } catch { self.error = error.localizedDescription }
        changed()
    }
}

private struct WhitegramAccountSettingsEntry: ItemListNodeEntry {
    let stableId: String
    let index: Int
    let title: String
    let shared: Bool?
    let accountId: Int64?
    var section: ItemListSectionId { return accountId == nil ? 1 : 0 }
    static func <(lhs: Self, rhs: Self) -> Bool { return lhs.index < rhs.index }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let shared, let accountId {
            let coordinator = arguments as! WhitegramAccountSettingsCoordinator
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title,
                value: shared, maximumNumberOfLines: 0, sectionId: section, style: .blocks,
                updated: { coordinator.useShared($0, accountId: accountId) })
        }
        return ItemListTextItem(presentationData: presentationData, text: .plain(title), sectionId: section, style: .blocks)
    }
}

public func whitegramAccountSettingsController(context: AccountContext) -> ViewController {
    let coordinator = WhitegramAccountSettingsCoordinator(context: context)
    let signal = combineLatest(context.sharedContext.presentationData, context.sharedContext.activeAccountsWithInfo, coordinator.revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, accounts, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let language = presentationData.strings.baseLanguageCode
        var rows: [WhitegramAccountSettingsEntry] = []
        for item in accounts.accounts {
            let id = item.account.id.int64
            do {
                let shared = try !WhitegramPreferences.usesSeparateSettings(accountId: id)
                let mode = WhitegramLocalization.string(shared ? "accountSettings.shared" : "accountSettings.private", baseLanguage: language)
                let title = (accounts.primary == item.account.id ? "✓ " : "") + item.peer.debugDisplayTitle + " · " + mode
                rows.append(WhitegramAccountSettingsEntry(stableId: String(id), index: rows.count, title: title, shared: shared, accountId: id))
            } catch {
                rows.append(WhitegramAccountSettingsEntry(stableId: String(id), index: rows.count, title: item.peer.debugDisplayTitle + ": " + error.localizedDescription, shared: nil, accountId: nil))
            }
        }
        let info = WhitegramLocalization.string("accountSettings.info", baseLanguage: language)
        rows.append(WhitegramAccountSettingsEntry(stableId: "info", index: rows.count, title: info, shared: nil, accountId: nil))
        if let error = coordinator.error {
            rows.append(WhitegramAccountSettingsEntry(stableId: "error", index: rows.count, title: error, shared: nil, accountId: nil))
        }
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data,
            title: .text(WhitegramLocalization.string("accountSettings.title", baseLanguage: language)), leftNavigationButton: nil,
            rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        return (state, (ItemListNodeState(presentationData: data, entries: rows, style: .blocks, animateChanges: false), coordinator))
    }
    return ItemListController(context: context, state: signal)
}
