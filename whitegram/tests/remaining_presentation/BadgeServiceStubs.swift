import Foundation

enum WhitegramBackendError: Error { case unavailable }
protocol WhitegramBackendTask: AnyObject { func cancel() }
final class TestBadgeTask: WhitegramBackendTask {
    var cancelled = false
    func cancel() { cancelled = true }
}
struct WhitegramBackendSession: Equatable {
    let userId: Int64
    let expiresAt: Date
    func validate(userId: Int64, now: Date) throws {
        if self.userId != userId || expiresAt <= now { throw WhitegramBackendError.unavailable }
    }
}
final class TestBadgeSessions {
    func load(userId: Int64) throws -> WhitegramBackendSession? { TestBadgeBackend.sessions[userId] }
}
final class WhitegramBackendAccessStore {
    static let updated = Notification.Name("TestBackendAccessUpdated")
    func require(userId: Int64, path: String, now: Date) throws {
        precondition(path == "/v1/profile/badge")
        if !TestBadgeBackend.allowed.contains(userId) { throw WhitegramBackendError.unavailable }
    }
}
final class WhitegramBackendClient {
    static let sessionUpdated = Notification.Name("TestBackendSessionUpdated")
    let userId: Int64
    let sessions = TestBadgeSessions()
    let access = WhitegramBackendAccessStore()
    let now: () -> Date = { TestBadgeBackend.now }
    init(userId: Int64) { self.userId = userId }
}
struct WhitegramProfileBadge: Decodable {
    let granted: Bool?
    let role: String?
    let badgeText: String?
    let verificationText: String?
}
enum WhitegramProfileResource { case badge
    var path: String { "/v1/profile/badge" }
}
enum TestBadgeBackend {
    static var now = Date(timeIntervalSince1970: 1_000)
    static var sessions: [Int64: WhitegramBackendSession] = [:]
    static var allowed = Set<Int64>()
    static var requests: [(Int64, Int64, TestBadgeTask, (WhitegramProfileBadge) -> Void)] = []
    static let granted = WhitegramProfileBadge(granted: true, role: nil, badgeText: nil, verificationText: nil)
}
final class WhitegramProfileService {
    static let updated = Notification.Name("TestBackendProfileUpdated")
    let client: WhitegramBackendClient
    init(client: WhitegramBackendClient) { self.client = client }
    func fetch<T: Decodable>(_ type: T.Type, resource: WhitegramProfileResource, userId: Int64,
                             completion: @escaping (Result<T, WhitegramBackendError>) -> Void) -> WhitegramBackendTask {
        precondition(type == WhitegramProfileBadge.self)
        let task = TestBadgeTask()
        // Deliberately permits a callback after cancel to exercise generation guards.
        TestBadgeBackend.requests.append((client.userId, userId, task, { completion(.success($0 as! T)) }))
        return task
    }
}
func whitegramServiceObserve(_ name: Notification.Name, action: @escaping (Notification) -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in action(notification) }
}
