import Foundation
import UIKit
import TelegramCore

public func whitegramClientInterfaceTheme(_ theme: PresentationTheme) -> PresentationTheme {
    guard WhitegramClientInterfaceSettings.current.oled, theme.overallDarkAppearance else { return theme }
    let black = UIColor.black
    let surface = UIColor(rgb: 0x0d0d0d)
    let raised = UIColor(rgb: 0x0f0f0f)
    let root = theme.rootController.withUpdated(
        tabBar: theme.rootController.tabBar.withUpdated(backgroundColor: black),
        navigationBar: theme.rootController.navigationBar.withUpdated(blurredBackgroundColor: black.withAlphaComponent(0.7), opaqueBackgroundColor: black),
        navigationSearchBar: theme.rootController.navigationSearchBar.withUpdated(backgroundColor: black, inputFillColor: raised)
    )
    let list = theme.list.withUpdated(blocksBackgroundColor: black, modalBlocksBackgroundColor: black,
        plainBackgroundColor: black, modalPlainBackgroundColor: black,
        itemBlocksBackgroundColor: surface, itemModalBlocksBackgroundColor: raised)
    let chatList = theme.chatList.withUpdated(backgroundColor: black, itemBackgroundColor: surface,
        pinnedItemBackgroundColor: surface, itemHighlightedBackgroundColor: UIColor(rgb: 0x161616),
        pinnedItemHighlightedBackgroundColor: UIColor(rgb: 0x1a1a1a))
    let chat = theme.chat.withUpdated(inputPanel: theme.chat.inputPanel.withUpdated(panelBackgroundColor: black,
        panelBackgroundColorNoWallpaper: black, inputBackgroundColor: raised))
    let result = PresentationTheme(name: theme.name, index: theme.index, referenceTheme: theme.referenceTheme,
        overallDarkAppearance: theme.overallDarkAppearance, intro: theme.intro, passcode: theme.passcode,
        rootController: root, list: list, chatList: chatList, chat: chat,
        actionSheet: theme.actionSheet.withUpdated(opaqueItemBackgroundColor: surface, itemBackgroundColor: surface),
        contextMenu: theme.contextMenu.withUpdated(backgroundColor: black, itemBackgroundColor: surface),
        inAppNotification: theme.inAppNotification, chart: theme.chart, preview: theme.preview)
    result.starGift = theme.starGift
    result.forceSync = theme.forceSync
    return result
}
