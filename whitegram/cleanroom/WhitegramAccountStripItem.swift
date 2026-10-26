import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AvatarNode
import AccountContext
import TelegramCore
import TelegramPresentationData
import SwiftSignalKit

final class WhitegramAccountStripItem: PeerInfoScreenItem {
    let id: AnyHashable = "whitegram-account-strip"
    let accounts: [(AccountContext, EnginePeer, Int32)]
    let actions: [PeerInfoScreenActionItem]
    let interaction: PeerInfoInteraction

    init(accounts: [(AccountContext, EnginePeer, Int32)], actions: [PeerInfoScreenActionItem], interaction: PeerInfoInteraction) {
        self.accounts = accounts
        self.actions = actions
        self.interaction = interaction
    }

    func node() -> PeerInfoScreenItemNode { return WhitegramAccountStripNode() }
}

private final class WhitegramAccountStripButton: UIButton {
    let avatar = AvatarNode(font: Font.regular(20))
    let caption = UILabel()
    let badge = UILabel()
    var activate: (() -> Void)?
    var moveEarlier: (() -> Void)?
    var moveLater: (() -> Void)?
    var accountMenu: (() -> Void)?
    var accountId: Int64?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(avatar.view)
        avatar.isUserInteractionEnabled = false
        caption.font = Font.regular(11)
        caption.textAlignment = .center
        caption.numberOfLines = 2
        addSubview(caption)
        badge.font = Font.semibold(11)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        addSubview(badge)
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView?.frame = CGRect(x: 24, y: 18, width: 28, height: 28)
        imageView?.contentMode = .scaleAspectFit
    }
    @objc private func pressed() { activate?() }
    @objc func earlier() -> Bool { moveEarlier?(); return moveEarlier != nil }
    @objc func later() -> Bool { moveLater?(); return moveLater != nil }
    @objc func menu() -> Bool { accountMenu?(); return accountMenu != nil }
}

private final class WhitegramAccountStripNode: PeerInfoScreenItemNode {
    private let scroll = UIScrollView()
    private var buttons: [WhitegramAccountStripButton] = []
    private var item: WhitegramAccountStripItem?
    private var drag: (id: Int64, snapshot: [Int64])?
    private let reorderDisposable = MetaDisposable()
    private let recordsDisposable = MetaDisposable()
    private var orderedIds: [Int64] = []
    private var observedContext: AccountContext?
    private var refresh: (() -> Void)?

    override init() {
        super.init()
        scroll.showsHorizontalScrollIndicator = false
        view.addSubview(scroll)
        scroll.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(dragged)))
    }

    deinit { reorderDisposable.dispose(); recordsDisposable.dispose() }

    override func update(context: AccountContext, width: CGFloat, safeInsets: UIEdgeInsets, presentationData: PresentationData,
                         item: PeerInfoScreenItem, topItem: PeerInfoScreenItem?, bottomItem: PeerInfoScreenItem?,
                         hasCorners: Bool, transition: ContainedViewLayoutTransition) -> CGFloat {
        guard let item = item as? WhitegramAccountStripItem else { return 0 }
        self.item = item
        self.refresh = { [weak self] in
            guard let self else { return }
            let _ = self.update(context: context, width: width, safeInsets: safeInsets, presentationData: presentationData,
                item: item, topItem: topItem, bottomItem: bottomItem, hasCorners: hasCorners, transition: .immediate)
        }
        if observedContext !== context {
            observedContext = context
            recordsDisposable.set((context.sharedContext.accountManager.accountRecords() |> deliverOnMainQueue).start(next: { [weak self] view in
                guard let self else { return }
                func rank(_ record: AccountRecord<TelegramAccountRecordAttribute>) -> Int32 {
                    for attribute in record.attributes { if case let .sortOrder(value) = attribute { return value.order } }
                    return 0
                }
                let ids = view.records.sorted { lhs, rhs in
                    let left = rank(lhs), right = rank(rhs)
                    return left == right ? lhs.id.int64 < rhs.id.int64 : left < right
                }.map { $0.id.int64 }
                if ids != self.orderedIds { self.orderedIds = ids; self.refresh?() }
            }))
        }
        let rank = Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($0.element, $0.offset) })
        let accounts = item.accounts.sorted { (rank[$0.0.account.id.int64] ?? Int.max) < (rank[$1.0.account.id.int64] ?? Int.max) }
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        scroll.backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        scroll.layer.cornerRadius = hasCorners ? 12 : 0
        scroll.frame = CGRect(x: safeInsets.left, y: 0, width: max(0, width - safeInsets.left - safeInsets.right), height: 102)
        let ids = accounts.map { $0.0.account.id.int64 }
        for (index, entry) in accounts.enumerated() {
            let (accountContext, peer, count) = entry
            let button = makeButton(index: buttons.count, theme: presentationData.theme)
            button.accountId = accountContext.account.id.int64
            button.avatar.setPeerV2(context: accountContext, theme: presentationData.theme, peer: peer, displayDimensions: CGSize(width: 48, height: 48))
            button.caption.text = peer.debugDisplayTitle
            button.accessibilityLabel = peer.debugDisplayTitle
            button.accessibilityValue = count > 0 ? String(count) : nil
            button.badge.text = count > 999 ? "999+" : String(count)
            button.badge.isHidden = count == 0
            if accountContext.account.id == context.account.id {
                button.avatar.view.layer.borderColor = presentationData.theme.list.itemAccentColor.cgColor
                button.avatar.view.layer.borderWidth = 2
                button.accessibilityTraits.insert(.selected)
            }
            button.activate = {
                if accountContext.account.id != context.account.id { item.interaction.switchToAccount(accountContext.account.id) }
            }
            button.accountMenu = { [weak button] in
                guard let button, accountContext.account.id != context.account.id else { return }
                item.interaction.accountContextMenu(accountContext.account.id, button.avatar, nil)
            }
            if index > 0 {
                button.moveEarlier = { [weak self] in self?.move(ids[index], before: ids[index - 1], snapshot: ids) }
            }
            if index + 1 < ids.count {
                button.moveLater = { [weak self] in
                    var next = ids
                    next.swapAt(index, index + 1)
                    self?.commit(next, snapshot: ids)
                }
            }
            button.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "Move earlier", target: button, selector: #selector(WhitegramAccountStripButton.earlier)),
                UIAccessibilityCustomAction(name: "Move later", target: button, selector: #selector(WhitegramAccountStripButton.later)),
                UIAccessibilityCustomAction(name: "Account menu", target: button, selector: #selector(WhitegramAccountStripButton.menu))
            ]
        }
        for action in item.actions {
            let button = makeButton(index: buttons.count, theme: presentationData.theme)
            button.avatar.isHidden = true
            button.setImage(action.icon?.withRenderingMode(.alwaysTemplate), for: .normal)
            button.caption.text = action.text
            button.accessibilityLabel = action.text
            button.activate = action.action
        }
        scroll.contentSize = CGSize(width: CGFloat(buttons.count) * 76 + 16, height: 102)
        return 102
    }

    private func makeButton(index: Int, theme: PresentationTheme) -> WhitegramAccountStripButton {
        let button = WhitegramAccountStripButton(frame: CGRect(x: 8 + CGFloat(index) * 76, y: 4, width: 76, height: 94))
        button.tintColor = theme.list.itemAccentColor
        button.avatar.frame = CGRect(x: 14, y: 6, width: 48, height: 48)
        button.avatar.view.layer.cornerRadius = 24
        button.avatar.view.clipsToBounds = true
        button.caption.textColor = theme.list.itemPrimaryTextColor
        button.caption.frame = CGRect(x: 2, y: 60, width: 72, height: 30)
        button.badge.frame = CGRect(x: 46, y: 4, width: 28, height: 18)
        button.badge.backgroundColor = theme.chatList.unreadBadgeActiveBackgroundColor
        button.badge.textColor = theme.chatList.unreadBadgeActiveTextColor
        button.badge.isHidden = true
        scroll.addSubview(button)
        buttons.append(button)
        return button
    }

    @objc private func dragged(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: scroll)
        switch gesture.state {
        case .began:
            guard !WhitegramPreferences.bool("hideSettingsReorderAccounts"),
                  let button = buttons.first(where: { $0.frame.contains(point) }), let id = button.accountId else { return }
            drag = (id, buttons.compactMap { $0.accountId })
            button.alpha = 0.5
        case .changed:
            guard drag != nil else { return }
            let local = gesture.location(in: view).x
            let delta: CGFloat = local < 40 ? -24 : (local > view.bounds.width - 40 ? 24 : 0)
            let maximum = max(0, scroll.contentSize.width - scroll.bounds.width)
            scroll.contentOffset.x = min(maximum, max(0, scroll.contentOffset.x + delta))
        case .ended:
            if let drag, let target = buttons.first(where: { $0.frame.contains(point) })?.accountId {
                move(drag.id, before: target, snapshot: drag.snapshot)
            }
            finishDrag()
        case .cancelled, .failed:
            finishDrag()
        default:
            break
        }
    }

    private func finishDrag() {
        drag = nil
        for button in buttons { button.alpha = 1 }
    }

    private func move(_ id: Int64, before target: Int64, snapshot: [Int64]) {
        guard let result = WhitegramAccountStripOrder.moving(id, before: target, snapshot: snapshot, live: item?.accounts.map({ $0.0.account.id.int64 }) ?? []) else { return }
        commit(result, snapshot: snapshot)
    }

    private func commit(_ order: [Int64], snapshot: [Int64]) {
        guard WhitegramClientInterfaceSettings.current.accountStrip, !WhitegramPreferences.bool("hideSettingsReorderAccounts"),
              let context = item?.accounts.first?.0, Set(order) == Set(snapshot), order.count == Set(order).count else { return }
        reorderDisposable.set(context.sharedContext.accountManager.transaction { transaction -> Void in
            let records = transaction.getRecords().filter { record in
                record.temporarySessionId == nil && !record.attributes.contains(where: { if case .loggedOut = $0 { return true }; return false })
            }
            guard Set(records.map { $0.id.int64 }) == Set(snapshot) else { return }
            for (index, id) in order.enumerated() {
                transaction.updateRecord(AccountRecordId(rawValue: id)) { record in
                    guard let record else { return nil }
                    var attributes = record.attributes.filter { if case .sortOrder = $0 { return false }; return true }
                    attributes.append(.sortOrder(AccountSortOrderAttribute(order: Int32(index))))
                    return AccountRecord(id: record.id, attributes: attributes, temporarySessionId: record.temporarySessionId)
                }
            }
        }.start())
    }
}
