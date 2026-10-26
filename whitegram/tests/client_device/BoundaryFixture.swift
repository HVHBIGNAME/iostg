import Foundation
import Postbox
import SwiftSignalKit

enum Namespaces {
    enum Peer {
        static let CloudUser: Int32 = 0, CloudGroup: Int32 = 1, CloudChannel: Int32 = 2, SecretChat: Int32 = 3
    }
    enum Message {
        static let Local: Int32 = 0, ScheduledLocal: Int32 = 1, ScheduledCloud: Int32 = 2, Cloud: Int32 = 3
        static let allScheduled: Set<Int32> = [ScheduledLocal, ScheduledCloud]
    }
}
let viewOnceTimeout: Int32 = .max
final class OutgoingScheduleInfoMessageAttribute: MessageAttribute {
    let scheduleTime: Int32
    let repeatPeriod: Int32?
    init(scheduleTime: Int32, repeatPeriod: Int32?) { self.scheduleTime = scheduleTime; self.repeatPeriod = repeatPeriod }
}
final class AutoremoveTimeoutMessageAttribute: MessageAttribute {
    let timeout: Int32
    init(timeout: Int32) { self.timeout = timeout }
}
final class AutoclearTimeoutMessageAttribute: MessageAttribute {
    let timeout: Int32
    init(timeout: Int32) { self.timeout = timeout }
}
final class PaidStarsMessageAttribute: MessageAttribute {}
public enum EnqueueMessage {
    case message(String, [MessageAttribute], Int, Int, Int, Int, Int, Int, Int64?, Int)
    case forward(MessageId, Int, Int, [MessageAttribute], Int64?)
    var attributes: [MessageAttribute] {
        switch self { case let .message(_, a, _, _, _, _, _, _, _, _), let .forward(_, _, _, a, _): return a }
    }
    var correlation: Int64? {
        switch self { case let .message(_, _, _, _, _, _, _, _, c, _), let .forward(_, _, _, _, c): return c }
    }
    func withUpdatedCorrelationId(_ value: Int64?) -> Self {
        switch self {
        case let .message(t, a, b, c, d, e, f, g, _, h): return .message(t, a, b, c, d, e, f, g, value, h)
        case let .forward(s, t, g, a, _): return .forward(s, t, g, a, value)
        }
    }
    func withUpdatedAttributes(_ f: ([MessageAttribute]) -> [MessageAttribute]) -> Self {
        switch self {
        case let .message(t, a, b, c, d, e, g, h, i, j): return .message(t, f(a), b, c, d, e, g, h, i, j)
        case let .forward(s, t, g, a, c): return .forward(s, t, g, f(a), c)
        }
    }
}
struct Message { let timestamp: Int32; let scheduleTime: Int32? }
public final class Account {
    let postbox = PostboxFixture()
    let pendingMessageManager = PendingFixture()
    let stateManager = 0
}
final class PendingFixture {
    var mapping: [Int64: MessageId] = [:]
    func synchronouslyLookupCorrelationId(correlationId: Int64) -> MessageId? { mapping[correlationId] }
}
final class Transaction {
    var messages: [MessageId: Message] = [:]
    var deleted: [MessageId] = []
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
}
final class PostboxFixture {
    let transactionValue = Transaction()
    var beforeTransaction: (() -> Void)?
    func transaction<T>(_ f: (Transaction) -> T) -> Signal<T, NoError> { beforeTransaction?(); return Signal(f(transactionValue)) }
}
enum DeletionType { case forEveryone }
func deleteMessagesInteractively(transaction: Transaction, stateManager: Int, postbox: PostboxFixture, messageIds: [MessageId], type: DeletionType, removeIfPossiblyDelivered: Bool) {
    precondition(!removeIfPossiblyDelivered)
    transaction.deleted += messageIds
    for id in messageIds { transaction.messages.removeValue(forKey: id) }
}
