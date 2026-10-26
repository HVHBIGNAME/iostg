import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LottieSettings

final class WhitegramClassicTabRenderer {
    private var node: TabBarNode?
    private var items: [UITabBarItem] = []

    func update(host: ASDisplayNode, frame: CGRect, layout: ContainerViewLayout, theme: PresentationTheme, items: [TabBarNodeItem], selected: Int,
                enabled: Bool, hidden: Bool, interactionEnabled: Bool, reduceMotion: Bool, transition: ContainedViewLayoutTransition,
                select: @escaping (Int, Bool, [ASDisplayNode]) -> Void, swipe: @escaping (Int, TabBarItemSwipeDirection) -> Void) {
        guard enabled else {
            self.node?.removeFromSupernode()
            self.node = nil
            self.items = []
            return
        }
        let node: TabBarNode
        if let current = self.node { node = current }
        else {
            node = TabBarNode(theme: theme, itemSelected: select,
                contextAction: { index, source, gesture in
                    gesture.cancel()
                    select(index, true, [source])
                }, swipeAction: swipe, lottieSettings: .noAccountFallback)
            self.node = node
            host.addSubnode(node)
        }
        node.updateTheme(theme)
        let tabItems = items.map(\.item)
        if tabItems.count != self.items.count || zip(tabItems, self.items).contains(where: { $0.0 !== $0.1 }) {
            self.items = tabItems
            node.tabBarItems = items
        }
        node.selectedIndex = selected
        node.reduceMotion = reduceMotion
        node.isHidden = hidden
        node.view.accessibilityElementsHidden = hidden
        node.isUserInteractionEnabled = !hidden && interactionEnabled
        transition.updateFrame(node: node, frame: frame)
        node.updateLayout(size: frame.size, leftInset: layout.safeInsets.left, rightInset: layout.safeInsets.right,
            additionalSideInsets: .zero, bottomInset: layout.insets(options: []).bottom, transition: transition)
        host.view.bringSubviewToFront(node.view)
    }

    func frame(index: Int, in view: UIView) -> CGRect? {
        guard let node, !node.isHidden, index >= 0, index < self.items.count,
              let frame = node.frameForControllerTab(at: index) else { return nil }
        return view.convert(frame, from: node.view)
    }
}
