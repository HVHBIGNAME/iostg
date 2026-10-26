import Foundation
import Postbox

@main enum WhitegramDeviceTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
        let suite = "whitegram-client-device-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stock = WhitegramDeviceSettings(values: [:])
        check(stock.connectionDeviceModel(fallback: "iPhone") == "iPhone" && !stock.deferredMessages, "stock defaults")
        check(WhitegramDeviceSettings.normalizedDeviceName(" \n Mac Pro \t") == "Mac Pro", "original editor trims")
        check(WhitegramDeviceSettings(values: ["fakeDeviceName": "  "]).connectionDeviceModel(fallback: "iPhone") == "  ", "wire consumer does not trim again")
        defaults.set("Work device", forKey: "wg_fakeDeviceName")
        defaults.set(true, forKey: "wg_deferredMessages")
        check(WhitegramDeviceSettings(values: [:], legacyDefaults: defaults).fakeDeviceName == "Work device", "legacy mirror")
        check(WhitegramDeviceSettings(values: ["fakeDeviceName": ""], legacyDefaults: defaults).fakeDeviceName == "", "canonical clear wins")
        check(!WhitegramDeviceSettings(values: ["deferredMessages": 1]).deferredMessages, "strict bool")
        check(WhitegramPreferences.update(["fakeDeviceName": "Session label"]), "save")
        check(UserDefaults.standard.string(forKey: "wg_fakeDeviceName") == "Session label", "MTProto mirror")
        let enabled = WhitegramDeviceSettings(values: ["deferredMessages": true])
        check(enabled.deferredDeadline(now: 100.9, cloudPeer: true, scheduledSubject: false, committed: false, postpone: false, hasSchedule: false, viewOnce: false, paid: false) == 112, "12 second timestamp")
        for now in [Double.nan, Double.infinity, -1, Double(Int32.max)] {
            check(enabled.deferredDeadline(now: now, cloudPeer: true, scheduledSubject: false, committed: false, postpone: false, hasSchedule: false, viewOnce: false, paid: false) == nil, "bad date")
        }
        for flag in 0..<7 {
            check(enabled.deferredDeadline(now: 100, cloudPeer: flag != 0, scheduledSubject: flag == 1, committed: flag == 2, postpone: flag == 3, hasSchedule: flag == 4, viewOnce: flag == 5, paid: flag == 6) == nil, "bypass \(flag)")
        }
        let peer = PeerId(namespace: Namespaces.Peer.CloudUser)
        func message(_ attributes: [MessageAttribute] = [], correlation: Int64? = nil) -> EnqueueMessage { .message("hello", attributes, 1, 2, 3, 4, 5, 6, correlation, 7) }
        let forward = EnqueueMessage.forward(MessageId(peerId: peer, namespace: 3, id: 99), 0, 1, [], 999)
        let batch = WhitegramDeviceDeferredMessages.prepare(messages: [message(correlation: 123), forward], peerId: peer, scheduledSubject: false, committed: false, postpone: false, settings: enabled, now: 100)
        check(batch.state?.deadline == 112, "prepared deadline")
        check(batch.messages.map(\.correlation) == [123, 999], "transition correlations preserved")
        check(batch.messages.allSatisfy { ($0.attributes.last as? OutgoingScheduleInfoMessageAttribute)?.scheduleTime == 112 }, "text and forwarded schedule consumers")
        let replay = WhitegramDeviceDeferredMessages.prepare(messages: batch.messages, peerId: peer, scheduledSubject: false, committed: false, postpone: false, settings: enabled, now: 105)
        check(replay.state == nil, "no repeated delay")
        for attrs: [MessageAttribute] in [[OutgoingScheduleInfoMessageAttribute(scheduleTime: 500, repeatPeriod: 20)], [AutoremoveTimeoutMessageAttribute(timeout: viewOnceTimeout)], [AutoclearTimeoutMessageAttribute(timeout: viewOnceTimeout)], [PaidStarsMessageAttribute()]] {
            check(WhitegramDeviceDeferredMessages.prepare(messages: [message(attrs)], peerId: peer, scheduledSubject: false, committed: false, postpone: false, settings: enabled, now: 100).state == nil, "special sends bypass")
        }
        let account = Account()
        let local = MessageId(peerId: peer, namespace: Namespaces.Message.ScheduledLocal, id: 1)
        let remote = MessageId(peerId: peer, namespace: Namespaces.Message.ScheduledCloud, id: 2)
        let sent = MessageId(peerId: peer, namespace: Namespaces.Message.Cloud, id: 3)
        account.postbox.transactionValue.messages = [local: Message(timestamp: 112, scheduleTime: 112), remote: Message(timestamp: 112, scheduleTime: nil), sent: Message(timestamp: 112, scheduleTime: nil)]
        account.pendingMessageManager.mapping = [123: remote, 999: sent]
        _ = WhitegramDeviceDeferredMessages.cancel(batch: batch, account: account, messageIds: [local], now: 111)
        check(Set(account.postbox.transactionValue.deleted) == [local, remote], "undo follows local-to-scheduled-cloud remapping and excludes sent messages")
        _ = WhitegramDeviceDeferredMessages.cancel(batch: batch, account: account, messageIds: [local], now: 111)
        check(account.postbox.transactionValue.deleted.count == 2, "duplicate undo")
        check(!WhitegramDeviceDeferredState(deadline: 112).cancel(now: 112), "deadline prevents late delete")
        let clock = Date().timeIntervalSince1970
        let pending = WhitegramDeviceDeferredMessages.prepare(messages: [message(correlation: 777)], peerId: peer, scheduledSubject: false, committed: false, postpone: false, settings: enabled, now: clock)
        let pendingAccount = Account()
        var transactions = 0
        pendingAccount.postbox.beforeTransaction = {
            transactions += 1
            if transactions == 2 {
                pendingAccount.pendingMessageManager.mapping[777] = remote
            }
            if transactions == 3 {
                pendingAccount.postbox.transactionValue.messages[remote] = Message(timestamp: pending.state!.deadline, scheduleTime: nil)
            }
        }
        _ = WhitegramDeviceDeferredMessages.cancel(batch: pending, account: pendingAccount, messageIds: [local], now: clock)
        check(pendingAccount.postbox.transactionValue.deleted == [remote], "undo follows late ack and late transaction application")
        check(transactions == 3, "reconciliation stops when remapping resolves")
        let unchanged = WhitegramDeviceDeferredMessages.prepare(messages: [message()], peerId: peer, scheduledSubject: false, committed: false, postpone: false, settings: stock, now: 100)
        check(unchanged.state == nil && unchanged.messages.first?.correlation == nil, "disabled preserves outgoing identity")
        check(WhitegramDeviceDeferredMessages.prepare(messages: [], peerId: peer, scheduledSubject: false, committed: false, postpone: false, settings: enabled, now: 100).state == nil, "empty selection")
        let race = WhitegramDeviceDeferredState(deadline: 112)
        let lock = NSLock()
        var wins = 0
        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            if race.cancel(now: 100) { lock.lock(); wins += 1; lock.unlock() }
        }
        check(wins == 1, "atomic cancellation")
        check(WhitegramMediaSettings(values: [:]).initialRoundVideoFrontCamera(selected: nil), "camera default front")
        for camera in 0...2 {
            let settings = WhitegramMediaSettings(values: ["videoMessageCamera": camera, "chooseCameraBeforeRoundVideo": true])
            check(settings.asksForRoundVideoCamera, "original picker bool independent from saved side")
            check(!settings.initialRoundVideoFrontCamera(selected: false), "picker choice wins")
            check(settings.initialRoundVideoFrontCamera(selected: nil) == (camera != 1), "saved camera mapping")
        }
        check(!WhitegramMediaSettings(values: ["chooseCameraBeforeRoundVideo": 1]).asksForRoundVideoCamera, "strict picker bool")
        check(WhitegramMediaSettings(values: ["videoMessageCamera": 2]).asksForRoundVideoCamera, "public ask remains supported")
        defaults.set(true, forKey: "wg_chooseCameraBeforeRoundVideo")
        check(WhitegramMediaSettings(values: [:], legacyDefaults: defaults).asksForRoundVideoCamera, "original picker mirror")
        check(!WhitegramMediaSettings(values: WhitegramMediaSettings.resetValues, legacyDefaults: defaults).asksForRoundVideoCamera, "reset overrides legacy picker")
        print("Whitegram device/camera policy and native boundary fixtures: \(checks) checks passed")
    }
}
