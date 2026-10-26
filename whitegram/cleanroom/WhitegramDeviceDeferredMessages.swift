import Foundation
import Postbox
import SwiftSignalKit

public enum WhitegramDeviceDeferredMessages {
    public struct Batch {
        public let messages: [EnqueueMessage]
        public let state: WhitegramDeviceDeferredState?
        fileprivate let correlations: [Int64]
    }

    public static func prepare(messages: [EnqueueMessage], peerId: PeerId, scheduledSubject: Bool, committed: Bool, postpone: Bool, settings: WhitegramDeviceSettings = .current, now: Double = Date().timeIntervalSince1970) -> Batch {
        let cloud = [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(peerId.namespace)
        let attributes = messages.flatMap(\.attributes)
        let viewOnce = attributes.contains { ($0 as? AutoremoveTimeoutMessageAttribute)?.timeout == viewOnceTimeout || ($0 as? AutoclearTimeoutMessageAttribute)?.timeout == viewOnceTimeout }
        let deadline = settings.deferredDeadline(now: now, cloudPeer: cloud, scheduledSubject: scheduledSubject, committed: committed, postpone: postpone,
            hasSchedule: attributes.contains { $0 is OutgoingScheduleInfoMessageAttribute }, viewOnce: viewOnce, paid: attributes.contains { $0 is PaidStarsMessageAttribute })
        guard !messages.isEmpty, let deadline else { return Batch(messages: messages, state: nil, correlations: []) }
        var correlations: [Int64] = []
        let prepared = messages.map { message -> EnqueueMessage in
            let correlation: Int64
            switch message {
            case let .message(_, _, _, _, _, _, _, _, value, _): correlation = value ?? Int64.random(in: 0 ..< Int64.max)
            case let .forward(_, _, _, _, value): correlation = value ?? Int64.random(in: 0 ..< Int64.max)
            }
            correlations.append(correlation)
            return message.withUpdatedCorrelationId(correlation).withUpdatedAttributes {
                return $0 + [OutgoingScheduleInfoMessageAttribute(scheduleTime: deadline, repeatPeriod: nil)]
            }
        }
        return Batch(messages: prepared, state: WhitegramDeviceDeferredState(deadline: deadline), correlations: correlations)
    }

    public static func cancel(batch: Batch, account: Account, messageIds: [MessageId?], now: Double = Date().timeIntervalSince1970) -> Signal<Void, NoError> {
        guard let state = batch.state, state.cancel(now: now) else { return .complete() }
        return reconcileCancellation(batch: batch, account: account, messageIds: messageIds, attempts: 48, deadline: state.deadline)
    }

    private static func reconcileCancellation(batch: Batch, account: Account, messageIds: [MessageId?], attempts: Int, deadline: Int32) -> Signal<Void, NoError> {
        // Upload/ack may replace a local scheduled ID after undo was tapped.
        // Keep following its correlation while the original undo window is open.
        return cancellationTransaction(batch: batch, account: account, messageIds: messageIds, deadline: deadline)
        |> mapToSignal { unresolved -> Signal<Void, NoError> in
            guard unresolved, attempts > 0, Date().timeIntervalSince1970 < Double(deadline) else { return .complete() }
            return (Signal<Void, NoError>.complete() |> delay(0.25, queue: Queue.mainQueue()))
            |> then(reconcileCancellation(batch: batch, account: account, messageIds: messageIds, attempts: attempts - 1, deadline: deadline))
        }
    }

    private static func cancellationTransaction(batch: Batch, account: Account, messageIds: [MessageId?], deadline: Int32) -> Signal<Bool, NoError> {
        return account.postbox.transaction { transaction -> Bool in
            var ids = Set(messageIds.compactMap { $0 })
            var unresolved = false
            for correlation in batch.correlations {
                if let id = account.pendingMessageManager.synchronouslyLookupCorrelationId(correlationId: correlation) {
                    ids.insert(id)
                } else {
                    unresolved = true
                }
            }
            let scheduled = ids.filter { id in
                guard Namespaces.Message.allScheduled.contains(id.namespace) else { return false }
                guard let message = transaction.getMessage(id) else {
                    if id.namespace == Namespaces.Message.ScheduledCloud { unresolved = true }
                    return false
                }
                return message.timestamp == deadline || message.scheduleTime == deadline
            }
            if !scheduled.isEmpty {
                deleteMessagesInteractively(transaction: transaction, stateManager: account.stateManager, postbox: account.postbox, messageIds: Array(scheduled), type: .forEveryone, removeIfPossiblyDelivered: false)
            }
            return unresolved
        }
    }
}
