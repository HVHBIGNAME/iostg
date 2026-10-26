import Foundation
import UIKit
import AsyncDisplayKit
import AccountContext
import Display
import TelegramCore
import TelegramPresentationData

/// Settings entrypoint for the parent-owned CLIENT menu/capability binding.
public func whitegramDeviceSettingsController(context: AccountContext) -> ViewController {
    return WhitegramDeviceSettingsController(context: context)
}

private final class WhitegramDeviceSettingsController: ViewController {
    private let context: AccountContext
    private let nameField = UITextField()
    private let delayedSwitch = UISwitch()

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        let data = self.context.sharedContext.currentPresentationData.with { $0 }
        let localize: (String) -> String = { WhitegramLocalization.string($0, baseLanguage: data.strings.baseLanguageCode) }
        self.title = localize("s.fakeDeviceName").replacingOccurrences(of: "\n", with: " ")
        self.displayNode.backgroundColor = data.theme.list.blocksBackgroundColor
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.displayNode.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.displayNode.view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: self.displayNode.view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: self.displayNode.view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
        func label(_ key: String) -> UILabel {
            let label = UILabel()
            label.numberOfLines = 0
            label.text = localize(key)
            label.textColor = data.theme.list.itemPrimaryTextColor
            return label
        }
        stack.addArrangedSubview(label("s.fakeDeviceName"))
        self.nameField.borderStyle = .roundedRect
        self.nameField.textColor = data.theme.list.itemPrimaryTextColor
        self.nameField.text = WhitegramDeviceSettings.current.fakeDeviceName
        self.nameField.autocorrectionType = .no
        self.nameField.autocapitalizationType = .none
        stack.addArrangedSubview(self.nameField)
        stack.addArrangedSubview(label("wh.fakeDeviceName"))
        let save = UIButton(type: .system)
        save.setTitle(localize("common.save"), for: .normal)
        save.addTarget(self, action: #selector(self.saveName), for: .touchUpInside)
        stack.addArrangedSubview(save)
        stack.addArrangedSubview(label("s.deferredMessages"))
        self.delayedSwitch.isOn = WhitegramDeviceSettings.current.deferredMessages
        self.delayedSwitch.addTarget(self, action: #selector(self.saveDelay), for: .valueChanged)
        stack.addArrangedSubview(self.delayedSwitch)
        stack.addArrangedSubview(label("wh.deferredMessages"))
        self.displayNodeDidLoad()
    }

    private func save(_ values: [String: Any]) -> Bool {
        if WhitegramPreferences.update(values) { return true }
        let data = self.context.sharedContext.currentPresentationData.with { $0 }
        let alert = UIAlertController(title: WhitegramLocalization.string("common.error", baseLanguage: data.strings.baseLanguageCode), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: data.strings.Common_OK, style: .default))
        self.present(alert, animated: true)
        return false
    }

    @objc private func saveName() {
        let name = WhitegramDeviceSettings.normalizedDeviceName(self.nameField.text ?? "")
        if self.save(["fakeDeviceName": name]) { self.nameField.text = name; self.nameField.resignFirstResponder() }
    }

    @objc private func saveDelay() {
        if !self.save(["deferredMessages": self.delayedSwitch.isOn]) { self.delayedSwitch.isOn = WhitegramDeviceSettings.current.deferredMessages }
    }
}
