import Foundation
import Display
import TelegramCore
import AccountContext

final class WhitegramFeedRootState {
    private let context: AccountContext
    private var enabled: Bool?
    private var controller: WhitegramFeedController?

    init(context: AccountContext) { self.context = context }

    var needsUpdate: Bool { return self.readEnabled() != self.enabled }

    private func readEnabled() -> Bool {
        do { return WhitegramNavigationPolicy.flag(try WhitegramNavigationSettings.values(accountId: self.context.account.id.int64)["showPostsFeed"]) }
        catch { NSLog("Whitegram: feed preference read failed: %@", error.localizedDescription); return self.enabled ?? false }
    }

    func controllers(base: [ViewController], parent: NavigationController) -> [ViewController] {
        let enabled = self.readEnabled()
        self.enabled = enabled
        guard enabled else { self.controller = nil; return base }
        let controller = self.controller ?? WhitegramFeedController(context: self.context)
        self.controller = controller
        controller.rootNavigation = parent
        var result = base
        result.insert(controller, at: max(0, result.count - 1))
        return result
    }
}
