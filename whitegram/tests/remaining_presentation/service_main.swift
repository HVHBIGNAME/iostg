import Foundation
import TelegramCore

@main enum RemainingBadgeServiceChecks {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ text: String) { count += 1; precondition(value(), text) }
        func drain(_ seconds: Double = 0.03) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        for id: Int64 in [10, 11] {
            TestBadgeBackend.sessions[id] = WhitegramBackendSession(userId: id, expiresAt: TestBadgeBackend.now.addingTimeInterval(60))
            TestBadgeBackend.allowed.insert(id)
        }
        whitegramInstallRemainingPresentation()
        whitegramInstallRemainingPresentation()
        var first: WhitegramRemainingBadgeBinding? = WhitegramRemainingBadgeBinding()
        var second: WhitegramRemainingBadgeBinding? = WhitegramRemainingBadgeBinding()
        let other = WhitegramRemainingBadgeBinding()
        first?.update(accountId: 10, userId: 20)
        second?.update(accountId: 10, userId: 20)
        check(TestBadgeBackend.requests.count == 1, "same-account peer requests coalesce")
        check(TestBadgeBackend.requests[0].0 == 10 && TestBadgeBackend.requests[0].1 == 20, "explicit backend identity")
        TestBadgeBackend.requests[0].3(TestBadgeBackend.granted)
        drain()
        check(first!.showsBadge(accountId: 10, userId: 20, surface: .post), "grant delivered to first subscriber")
        check(second!.showsBadge(accountId: 10, userId: 20, surface: .chatList), "grant delivered to second subscriber")
        other.update(accountId: 11, userId: 20)
        check(TestBadgeBackend.requests.count == 2, "same peer on different account is not shared")
        check(!other.showsBadge(accountId: 11, userId: 20, surface: .post), "other account cannot inherit grant")
        NotificationCenter.default.post(name: WhitegramProfileService.updated, object: nil, userInfo: ["accountId": Int64(10)])
        drain()
        check(TestBadgeBackend.requests.count == 3, "mutation coalesces replacement subscribers")
        check(!first!.showsBadge(accountId: 10, userId: 20, surface: .post), "mutation clears rendered grant")
        TestBadgeBackend.requests[0].3(TestBadgeBackend.granted)
        drain()
        check(!first!.showsBadge(accountId: 10, userId: 20, surface: .post), "late old response cannot repopulate")
        TestBadgeBackend.requests[2].3(WhitegramProfileBadge(granted: false, role: "admin", badgeText: "trusted", verificationText: "yes"))
        drain()
        check(!first!.showsBadge(accountId: 10, userId: 20, surface: .post), "explicit denial beats role")
        TestBadgeBackend.requests[1].3(TestBadgeBackend.granted)
        drain()
        check(other.showsBadge(accountId: 11, userId: 20, surface: .post), "independent grant")
        TestBadgeBackend.now = TestBadgeBackend.now.addingTimeInterval(61)
        drain(1.1)
        check(!other.showsBadge(accountId: 11, userId: 20, surface: .post), "silent session expiry removes badge")
        let before = TestBadgeBackend.requests.count
        NotificationCenter.default.post(name: WhitegramBackendClient.sessionUpdated, object: nil, userInfo: ["userId": Int64(10)])
        drain()
        check(TestBadgeBackend.requests.count == before, "expired account starts no HTTP")
        TestBadgeBackend.sessions[10] = WhitegramBackendSession(userId: 10, expiresAt: TestBadgeBackend.now.addingTimeInterval(60))
        NotificationCenter.default.post(name: WhitegramBackendClient.sessionUpdated, object: nil, userInfo: ["userId": Int64(10)])
        drain()
        check(TestBadgeBackend.requests.count == before + 1, "reauthorization restarts one shared request")
        let pending = TestBadgeBackend.requests.last!.2
        first = nil
        drain()
        check(!pending.cancelled, "one subscriber leaving does not cancel another")
        second = nil
        drain()
        check(pending.cancelled, "last subscriber cancels request")
        print("remaining badge service: \(count) production-adapter checks passed (synthetic backend)")
    }
}
