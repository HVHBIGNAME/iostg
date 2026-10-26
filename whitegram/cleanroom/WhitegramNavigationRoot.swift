import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import PeerInfoScreen
import TabBarUI

final class WhitegramNavigationRootState {
    private let context: AccountContext
    private var profile: PeerInfoScreenImpl?
    private var appliedPolicy: WhitegramNavigationPolicy?

    init(context: AccountContext) { self.context = context }

    var needsUpdate: Bool {
        do { return try WhitegramNavigationSettings.policy(accountId: self.context.account.id.int64) != self.appliedPolicy }
        catch { NSLog("Whitegram: navigation settings could not be read: %@", error.localizedDescription); return false }
    }

    func apply(to tab: TabBarControllerImpl, base: [ViewController], preferred: ViewController?, chats: ViewController, parent: NavigationController) {
        let policy: WhitegramNavigationPolicy
        do { policy = try WhitegramNavigationSettings.policy(accountId: self.context.account.id.int64) }
        catch {
            NSLog("Whitegram: navigation settings could not be read: %@", error.localizedDescription)
            if tab.controllers.isEmpty { tab.setControllers(base, selectedIndex: base.firstIndex(where: { $0 === chats })) }
            return
        }
        var controllers = base
        if policy.separateProfileTab {
            let profile: PeerInfoScreenImpl
            if let current = self.profile { profile = current }
            else {
                profile = PeerInfoScreenImpl(context: self.context, updatedPresentationData: nil, peerId: self.context.account.peerId,
                    avatarInitiallyExpanded: false, isOpenedFromChat: false, reactionSourceMessageId: nil, callMessages: [], isSettings: false, isMyProfile: true)
                self.profile = profile
            }
            profile.parentController = parent
            profile.tabBarItem.title = "Profile"
            profile.tabBarItem.image = UIImage(systemName: "person.crop.circle")
            profile.tabBarItem.selectedImage = UIImage(systemName: "person.crop.circle.fill")
            // Keep Settings ahead of Profile for existing stock first-match deep links.
            controllers.append(profile)
        }
        let previous = preferred ?? tab.currentController
        let keys = controllers.map { String(describing: ObjectIdentifier($0)) }
        let index = WhitegramNavigationPolicy.selection(previous: previous.map { String(describing: ObjectIdentifier($0)) }, available: keys, fallback: String(describing: ObjectIdentifier(chats)))
        self.appliedPolicy = policy
        tab.whitegramPersistentTabBarHidden = policy.hideBottomTabBar
        tab.whitegramRestoreTabBar = { [weak self, weak tab] in
            guard let self else { return }
            do { try WhitegramNavigationSettings.update(["hideBottomTabBar": false], accountId: self.context.account.id.int64) }
            catch {
                let alert = UIAlertController(title: "Could not restore tab bar", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                if var presenter = tab?.viewIfLoaded?.window?.rootViewController {
                    while let current = presenter.presentedViewController { presenter = current }
                    presenter.present(alert, animated: true)
                }
            }
        }
        tab.setControllers(controllers, selectedIndex: index)
        if !policy.separateProfileTab { self.profile = nil }
    }
}
