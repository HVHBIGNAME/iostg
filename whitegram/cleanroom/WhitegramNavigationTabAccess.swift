import UIKit
import Display

/// A top-edge escape route when the entire bottom tab view is removed from interaction and accessibility.
final class WhitegramNavigationTabAccess {
    private var button: UIButton?

    func update(host: UIView, layout: ContainerViewLayout, controllers: [ViewController], selected: Int, enabled: Bool, select: @escaping (Int) -> Void, restore: @escaping () -> Void) {
        guard enabled else {
            self.button?.removeFromSuperview()
            self.button = nil
            return
        }
        let button: UIButton
        if let current = self.button { button = current }
        else {
            button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "square.grid.2x2"), for: .normal)
            button.backgroundColor = .secondarySystemBackground
            button.layer.cornerRadius = 22.0
            button.accessibilityLabel = "Switch tab"
            button.accessibilityHint = "Choose a tab or restore the bottom tab bar."
            button.accessibilityIdentifier = "whitegram.hiddenTabs.access"
            button.showsMenuAsPrimaryAction = true
            self.button = button
        }
        var actions: [UIMenuElement] = controllers.enumerated().map { index, controller in
            UIAction(title: controller.tabBarItem.title ?? controller.title ?? "Tab \(index + 1)", image: controller.tabBarItem.image, state: selected == index ? .on : .off) { _ in select(index) }
        }
        actions.append(UIAction(title: "Show bottom tab bar", image: UIImage(systemName: "rectangle.bottomthird.inset.filled")) { _ in restore() })
        button.menu = UIMenu(children: actions)
        if button.superview !== host { host.addSubview(button) }
        host.bringSubviewToFront(button)
        button.frame = CGRect(x: layout.size.width - layout.safeInsets.right - 56.0, y: max(layout.safeInsets.top, layout.statusBarHeight ?? 0.0) + 56.0, width: 44.0, height: 44.0)
    }
}
