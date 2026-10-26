import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public struct WhitegramFeedPage {
    public let messages: [Message]
    public let nextOffset: Int32?
    public let exhausted: Bool
}

public enum WhitegramFeedHistoryError: Error {
    case unavailableChannel
    case request(String)
    case invalidPage
    case timeout
}

public enum WhitegramFeedHistory {
    public static func channels(account: Account) -> Signal<[TelegramChannel], NoError> {
        return account.postbox.transaction { transaction in
            let ids = Set(transaction.chatListGetAllPeerIds(groupId: .root) + transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive))
            return ids.compactMap { id -> TelegramChannel? in
                guard let channel = transaction.getPeer(id) as? TelegramChannel,
                      case .broadcast = channel.info, channel.participationStatus == .member else { return nil }
                return channel
            }.sorted { $0.id.toInt64() < $1.id.toInt64() }
        }
    }

    /// Same getHistory parameters as TelegramEngine.Messages.searchMessages' empty
    /// channel query, but preserves RPC failures instead of interpreting nil as EOF.
    public static func page(account: Account, peerId: PeerId, offset: Int32, limit: Int32 = 24) -> Signal<WhitegramFeedPage, WhitegramFeedHistoryError> {
        return account.postbox.transaction { transaction -> Api.InputPeer? in
            guard let channel = transaction.getPeer(peerId) as? TelegramChannel,
                  case .broadcast = channel.info, channel.participationStatus == .member else { return nil }
            return apiInputPeer(channel)
        }
        |> castError(WhitegramFeedHistoryError.self)
        |> mapToSignal { input -> Signal<WhitegramFeedPage, WhitegramFeedHistoryError> in
            guard let input else { return .fail(.unavailableChannel) }
            return account.network.request(Api.functions.messages.getHistory(peer: input, offsetId: offset, offsetDate: 0,
                addOffset: 0, limit: limit, maxId: Int32.max - 1, minId: 0, hash: 0), automaticFloodWait: false)
            |> mapError { WhitegramFeedHistoryError.request($0.errorDescription) }
            |> mapToSignal { result -> Signal<WhitegramFeedPage, WhitegramFeedHistoryError> in
                let apiMessages: [Api.Message]
                let users: [Api.User]
                let chats: [Api.Chat]
                switch result {
                case let .channelMessages(value): apiMessages = value.messages; users = value.users; chats = value.chats
                case let .messages(value): apiMessages = value.messages; users = value.users; chats = value.chats
                case let .messagesSlice(value): apiMessages = value.messages; users = value.users; chats = value.chats
                case .messagesNotModified: return .fail(.invalidPage)
                }
                return account.postbox.transaction { transaction -> WhitegramFeedPage in
                    var peers: [PeerId: Peer] = [:]
                    if let peer = transaction.getPeer(peerId) { peers[peerId] = peer }
                    for user in users {
                        if let peer = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) { peers[peer.id] = peer }
                    }
                    for chat in chats {
                        if let peer = parseTelegramGroupOrChannel(chat: chat) { peers[peer.id] = peer }
                    }
                    var messages: [Message] = []
                    var ids: [Int32] = []
                    for apiMessage in apiMessages {
                        // messageEmpty still advances a page containing deleted posts.
                        switch apiMessage {
                        case let .messageEmpty(value): ids.append(value.id)
                        case let .message(value): ids.append(value.id)
                        case let .messageService(value): ids.append(value.id)
                        }
                        guard let stored = StoreMessage(apiMessage: apiMessage, accountPeerId: account.peerId, peerIsForum: false),
                              let message = locallyRenderedMessage(message: stored, peers: peers, associatedThreadInfo: nil),
                              message.id.peerId == peerId, message.id.namespace == Namespaces.Message.Cloud,
                              !message.media.contains(where: { $0 is TelegramMediaAction }) else { continue }
                        messages.append(message)
                    }
                    return WhitegramFeedPage(messages: messages, nextOffset: ids.filter { $0 > 0 }.min(), exhausted: apiMessages.isEmpty)
                } |> castError(WhitegramFeedHistoryError.self)
            }
        }
        |> timeout(30.0, queue: .mainQueue(), alternate: .fail(.timeout))
    }
}
