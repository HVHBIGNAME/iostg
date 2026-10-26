import Foundation
import XCTest
import TelegramCore

final class WhitegramPluginServicesTests: XCTestCase {
    func testProviderQueueConsumerIdentityAndSingleSettlement() throws {
        let hub = WhitegramPluginServices(), account = NSObject(), queue = DispatchQueue(label: "PluginServices.provider")
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        let completed = expectation(description: "service completed")
        var token = ""
        let registration = try hub.register(scope: account, owner: "provider", name: "math", version: "2", queue: queue,
            permitted: { true }, invoke: { method, arguments, value, consumer in
                XCTAssertEqual(DispatchQueue.getSpecific(key: key), true)
                XCTAssertEqual(method, "add")
                XCTAssertEqual(consumer, "consumer")
                XCTAssertEqual(arguments as? [Int], [4, 5])
                token = value
                XCTAssertTrue(try! hub.resolve(scope: account, owner: "provider", token: value, response: ["ok": true, "value": 9]))
                XCTAssertFalse(try! hub.resolve(scope: account, owner: "provider", token: value, response: ["ok": true, "value": 99]))
            })
        let call = try hub.call(scope: account, consumer: "consumer", name: "math", method: "add", arguments: [4, 5], permitted: { true }, completion: { result in
            if case let .success(value) = result { XCTAssertEqual(value as? Int, 9) }
            else { XCTFail("Expected a service value") }
            completed.fulfill()
        })
        wait(for: [completed], timeout: 2)
        queue.sync { XCTAssertFalse(token.isEmpty) }
        call.dispose(); registration.dispose()
        XCTAssertTrue(hub.list(scope: account).isEmpty)
    }

    func testScopesOwnershipAndConsumerCannotForgeAResult() throws {
        let hub = WhitegramPluginServices(), account = NSObject(), other = NSObject(), queue = DispatchQueue(label: "PluginServices.isolation")
        var token = ""
        let invoked = expectation(description: "provider invoked"), finished = expectation(description: "provider cancelled")
        let registration = try hub.register(scope: account, owner: "provider", name: "wait", version: "1", queue: queue, permitted: { true }, invoke: { _, _, value, _ in token = value; invoked.fulfill() })
        XCTAssertThrowsError(try hub.register(scope: account, owner: "thief", name: "wait", version: "1", queue: queue, permitted: { true }, invoke: { _, _, _, _ in })) { error in
            XCTAssertEqual((error as? WhitegramPluginServiceError)?.code, "SERVICE_CONFLICT")
        }
        XCTAssertTrue(hub.list(scope: other).isEmpty)
        XCTAssertThrowsError(try hub.call(scope: other, consumer: "consumer", name: "wait", method: "read", arguments: [], permitted: { true }, completion: { _ in XCTFail("Cross-account service") }))
        let call = try hub.call(scope: account, consumer: "consumer", name: "wait", method: "read", arguments: [], permitted: { true }, completion: { result in
            if case let .failure(error) = result { XCTAssertEqual(error.code, "SERVICE_UNAVAILABLE") }
            else { XCTFail("Expected cancellation") }
            finished.fulfill()
        })
        wait(for: [invoked], timeout: 2)
        queue.sync {
            XCTAssertFalse(try! hub.resolve(scope: account, owner: "consumer", token: token, response: ["ok": true, "value": 42]))
            XCTAssertFalse(try! hub.resolve(scope: other, owner: "provider", token: token, response: ["ok": true, "value": 42]))
            XCTAssertThrowsError(try hub.resolve(scope: account, owner: "provider", token: token, response: ["ok": 1, "value": 42]))
        }
        registration.dispose()
        wait(for: [finished], timeout: 2)
        call.dispose()
    }

    func testConsumerDisposalAndReplacementCancelOutstandingCalls() throws {
        let hub = WhitegramPluginServices(), account = NSObject(), queue = DispatchQueue(label: "PluginServices.cancel")
        let first = try hub.register(scope: account, owner: "owner", name: "state", version: "1", queue: queue, permitted: { true }, invoke: { _, _, _, _ in })
        let cancelled = expectation(description: "consumer cancelled")
        let call = try hub.call(scope: account, consumer: "client", name: "state", method: "wait", arguments: [], permitted: { true }, completion: { result in
            if case let .failure(error) = result { XCTAssertEqual(error.code, "SERVICE_CANCELLED") }
            else { XCTFail("Expected cancellation") }
            cancelled.fulfill()
        })
        call.dispose(); call.dispose()
        wait(for: [cancelled], timeout: 2)
        let replaced = expectation(description: "provider replaced")
        let pending = try hub.call(scope: account, consumer: "client", name: "state", method: "wait", arguments: [], permitted: { true }, completion: { result in
            if case let .failure(error) = result { XCTAssertEqual(error.code, "SERVICE_UNAVAILABLE") }
            else { XCTFail("Expected replacement cancellation") }
            replaced.fulfill()
        })
        let second = try hub.register(scope: account, owner: "owner", name: "state", version: "2", queue: queue, permitted: { true }, invoke: { _, _, _, _ in })
        wait(for: [replaced], timeout: 2)
        first.dispose()
        XCTAssertEqual(hub.list(scope: account).first?["version"] as? String, "2")
        second.dispose(); pending.dispose()
    }
}
