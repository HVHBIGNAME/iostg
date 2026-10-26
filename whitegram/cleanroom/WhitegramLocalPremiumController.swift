import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils

public final class WhitegramLocalPremiumController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var observer: NSObjectProtocol?
    private let fields = ["nameColor", "nameBackgroundEmoji", "profileColor", "profileBackgroundEmoji", "emojiStatus"]
    private let labels = ["Name color", "Name background emoji ID", "Profile color", "Profile background emoji ID", "Emoji status file ID"]

    public init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }))
        self.title = "Local Premium"
        observer = NotificationCenter.default.addObserver(forName: WhitegramPreferences.updatedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.table.reloadData()
        }
    }

    required public init(coder: NSCoder) { return nil }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = context.sharedContext.currentPresentationData.with { $0.theme.list.blocksBackgroundColor }
        table.dataSource = self
        table.delegate = self
        self.displayNode.view.addSubview(table)
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        table.frame = CGRect(origin: .zero, size: layout.size)
        table.contentInset.top = self.navigationLayout(layout: layout).navigationFrame.maxY
        table.contentInset.bottom = layout.intrinsicInsets.bottom
    }

    public func numberOfSections(in tableView: UITableView) -> Int { return 2 }
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return section == 0 ? 1 : fields.count + 1 }
    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return section == 0 ? "Local profile presentation. Telegram server limits and subscription remain unchanged." : "Color indices start at 0. Emoji IDs must refer to available custom emoji. Clear a field to use the real profile value."
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        if indexPath.section == 0 {
            cell.textLabel?.text = "Local Premium"
            let toggle = UISwitch()
            toggle.isOn = WhitegramPreferences.bool("localPremium")
            toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
            cell.accessoryView = toggle
        } else if indexPath.row == fields.count {
            cell.textLabel?.text = "Reset local profile"
        } else {
            cell.textLabel?.text = labels[indexPath.row]
            let value = WhitegramLocalPremiumPresentation.current(accountId: context.account.id.int64).values[fields[indexPath.row]]
            cell.detailTextLabel?.text = value.map { String(describing: $0) } ?? "Real profile"
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    @objc private func toggled(_ toggle: UISwitch) {
        if !WhitegramPreferences.set(toggle.isOn, for: "localPremium") { toggle.isOn.toggle() }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let accountId = context.account.id.int64
        if indexPath.row == fields.count {
            if !WhitegramLocalPremiumPresentation.save(WhitegramLocalPremiumPolicy(), accountId: accountId) { showError() }
            return
        }
        let key = fields[indexPath.row]
        let alert = UIAlertController(title: labels[indexPath.row], message: "Leave empty to use the real profile value.", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = WhitegramLocalPremiumPresentation.current(accountId: accountId).values[key].map { String(describing: $0) }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var values = WhitegramLocalPremiumPresentation.current(accountId: accountId).values
            if text.isEmpty { values.removeValue(forKey: key) }
            else {
                let maximum = key == "nameColor" || key == "profileColor" ? Int64(Int32.max) : Int64.max
                guard let integer = WhitegramLocalPremiumPolicy.parseInteger(text, maximum: maximum) else { self.showError(); return }
                values[key] = integer
            }
            guard let policy = WhitegramLocalPremiumPolicy.decode(values), WhitegramLocalPremiumPresentation.save(policy, accountId: accountId) else { self.showError(); return }
        })
        presentAlert(alert)
    }

    private func showError() {
        let alert = UIAlertController(title: "Could not save local profile", message: "Check the value and saved settings.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }

    private func presentAlert(_ alert: UIAlertController) {
        guard var presenter = viewIfLoaded?.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(alert, animated: true)
    }
}
