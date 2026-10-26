import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    precondition(value(), label)
}
func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) }
typealias Policy = WhitegramRemainingPresentationPolicy

check(!Policy.hasGrantedBadge(granted: false, role: "admin", badgeText: "badge", verificationText: "verified"), "explicit denial beats metadata")
check(Policy.hasGrantedBadge(granted: true, role: nil, badgeText: nil, verificationText: nil), "explicit grant")
check(!Policy.hasGrantedBadge(granted: nil, role: "beta_tester", badgeText: nil, verificationText: nil), "beta access does not grant a badge")
check(!Policy.hasGrantedBadge(granted: nil, role: "", badgeText: "", verificationText: ""), "empty state")
check(Policy.hasGrantedBadge(granted: nil, role: "moderator", badgeText: nil, verificationText: nil), "legacy role")
check(Policy.hasGrantedBadge(granted: nil, role: "beta_tester", badgeText: "title", verificationText: nil), "legacy badge text")
check(Policy.hasGrantedBadge(granted: nil, role: nil, badgeText: nil, verificationText: "text"), "legacy verification text")
for surface in [WhitegramRemainingBadgeSurface.post, .chatList, .chatHeader] {
    check(!Policy.showsBadge(granted: true, hidden: true, surface: surface), "hide outside profile")
    check(Policy.showsBadge(granted: true, hidden: false, surface: surface), "show granted badge")
    check(!Policy.showsBadge(granted: false, hidden: false, surface: surface), "not granted")
}
check(Policy.showsBadge(granted: true, hidden: true, surface: .profile), "profile exemption")
for incoming in [false, true] {
    for hidden in [false, true] {
        check(Policy.allowsCustomMessageStyle(incoming: incoming, hidden: hidden, excluded: false, supportedMedia: true) == !(incoming && hidden), "incoming-only style gate")
        check(!Policy.allowsCustomMessageStyle(incoming: incoming, hidden: hidden, excluded: true, supportedMedia: true), "early exclusion gate")
        check(!Policy.allowsCustomMessageStyle(incoming: incoming, hidden: hidden, excluded: false, supportedMedia: false), "unsupported media excluded")
    }
}
check(Policy.appBadgeName(nil) == "WGBadgePrimary", "original default")
check(Policy.appBadgeName("") == "WGBadgePrimary", "empty original default")
check(Policy.appBadgeName("WGBadgeBlack") == "WGBadgeBlack", "name selector")

var completions: [(Bool) -> Void] = []
var requests: [(Int64, Int64)] = []
var cancellations = 0
WhitegramRemainingBadgeBinding.fetch = { account, user, completion in
    requests.append((account, user))
    completions.append(completion)
    return { cancellations += 1 }
}
var updates = 0
var binding: WhitegramRemainingBadgeBinding? = WhitegramRemainingBadgeBinding()
binding?.updated = { updates += 1 }
binding?.update(accountId: 10, userId: 20)
binding?.update(accountId: 10, userId: 20)
check(requests.count == 1, "deduplicates identical binding")
completions[0](true)
drain()
check(binding!.showsBadge(accountId: 10, userId: 20, surface: .post), "asynchronous grant renders")
check(!binding!.showsBadge(accountId: 11, userId: 20, surface: .post), "account isolation")
check(!binding!.showsBadge(accountId: 10, userId: 21, surface: .post), "peer isolation")
WhitegramPreferences.hidden = true
NotificationCenter.default.post(name: WhitegramPreferences.updatedNotification, object: nil)
drain()
check(!binding!.showsBadge(accountId: 10, userId: 20, surface: .chatList), "live hide preference")
check(binding!.showsBadge(accountId: 10, userId: 20, surface: .profile), "profile still visible")
WhitegramPreferences.hidden = false
binding?.update(accountId: 10, userId: 30)
check(cancellations == 1, "reuse cancels previous source")
completions[0](true)
drain()
check(!binding!.showsBadge(accountId: 10, userId: 30, surface: .post), "obsolete callback cannot label a new peer")
completions[1](true)
drain()
check(binding!.showsBadge(accountId: 10, userId: 30, surface: .post), "new peer response")
NotificationCenter.default.post(name: WhitegramRemainingBadgeBinding.invalidated, object: nil, userInfo: ["accountId": Int64(99)])
drain()
check(requests.count == 2, "unrelated account invalidation ignored")
NotificationCenter.default.post(name: WhitegramRemainingBadgeBinding.invalidated, object: nil, userInfo: ["accountId": Int64(10)])
drain()
check(requests.count == 3 && cancellations == 2, "logout/profile mutation invalidates and refetches")
check(!binding!.showsBadge(accountId: 10, userId: 30, surface: .post), "old grant removed immediately")
completions[1](true)
drain()
check(!binding!.showsBadge(accountId: 10, userId: 30, surface: .post), "pre-invalidation callback ignored")
binding?.update(accountId: 10, userId: nil)
completions[2](true)
drain()
check(!binding!.showsBadge(accountId: 10, userId: 30, surface: .post), "cleared binding cannot be resurrected")
binding?.update(accountId: 0, userId: 10)
check(requests.count == 3, "invalid account has no request")
binding?.update(accountId: 10, userId: -1)
check(requests.count == 3, "non-user id has no request")
binding?.update(accountId: 11, userId: 30)
check(requests.last!.0 == 11, "new account passed to backend")
binding = nil
check(cancellations == 4, "teardown cancels final source")
let lastUpdates = updates
completions[3](true)
drain()
check(updates == lastUpdates, "teardown suppresses callbacks")
print("remaining presentation: \(checks) policy/lifecycle checks passed")
