import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext

public enum ChatListNodeLocation {
    case initial(filter: ChatListFilter?), navigation(filter: ChatListFilter?)
    public var filter: ChatListFilter? { switch self { case let .initial(filter), let .navigation(filter): return filter } }
}
public enum ViewUpdateType { case Initial, Generic }
public struct ChatListNodeViewUpdate {
    public let list: EngineChatList
    public let type: ViewUpdateType
    public let scrollPosition: Int?
    public init(list: EngineChatList, type: ViewUpdateType, scrollPosition: Int?) { self.list = list; self.type = type; self.scrollPosition = scrollPosition }
}
var baseFixture = EngineChatList(items: [])
var additionalWindow = 0
func chatListNodeViewUpdateWithCommunitySummaries(account: Account, update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> { .single(update) }
func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListNodeLocation, account: Account, shouldLoadCanMessagePeer: Bool, whitegramAdditionalCount: Int = 0) -> Signal<ChatListNodeViewUpdate, NoError> {
    additionalWindow = whitegramAdditionalCount
    return .single(ChatListNodeViewUpdate(list: baseFixture, type: .Initial, scrollPosition: nil))
}
