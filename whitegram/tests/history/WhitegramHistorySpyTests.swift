import Foundation
import XCTest
@testable import WhitegramHistory

final class WhitegramHistorySpyTests: XCTestCase {
    func testExactMessageReadDatesReplayMonotonicPresenceAndAccountIsolation() throws {
        let suite = "whitegram-spy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = WhitegramSpyStore(accountId: 101, defaults: defaults)
        try first.record(peerId: 201, lastOnline: 1700000050)
        try first.record(peerId: 201, lastOnline: 1700000000)
        try first.record(peerId: 201, messageId: 7, readDate: 1700000055)
        try first.record(peerId: 201, messageId: 7, readDate: 1700000060)
        let reopened = WhitegramSpyStore(accountId: 101, defaults: defaults)
        XCTAssertEqual(try reopened.lastOnline(peerId: 201), 1700000050)
        XCTAssertEqual(try reopened.readDate(peerId: 201, messageId: 7), 1700000055)
        XCTAssertNil(try reopened.readDate(peerId: 201, messageId: 6))
        XCTAssertNil(try reopened.readDate(peerId: 202, messageId: 7))
        XCTAssertTrue(try WhitegramSpyStore(accountId: 102, defaults: defaults).snapshot().isEmpty)
    }

    func testMalformedAndForeignStoresArePreserved() throws {
        let suite = "whitegram-spy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WhitegramSpyStore(accountId: 101, defaults: defaults)
        for data in [Data("bad".utf8), Data("{\"version\":1,\"accountId\":102,\"peers\":{}}".utf8)] {
            defaults.set(data, forKey: store.storageKey)
            XCTAssertThrowsError(try store.record(peerId: 201, lastOnline: 1700000050))
            XCTAssertThrowsError(try store.snapshot())
            XCTAssertEqual(defaults.data(forKey: store.storageKey), data)
        }
    }

    func testInvalidAndSelfEvidenceNeverCreatesRecords() throws {
        let suite = "whitegram-spy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WhitegramSpyStore(accountId: 101, defaults: defaults)
        for peer in [Int64(-1), 0, 101, (Int64(2) << 32) | 201] { try store.record(peerId: peer, lastOnline: 1) }
        try store.record(peerId: 201, messageId: 0, readDate: 1)
        try store.record(peerId: 201, messageId: 7)
        try store.record(peerId: 201, lastOnline: -1)
        XCTAssertTrue(try store.snapshot().isEmpty)
    }

    func testReadDateLimitEvictsOldestExactIdentityAndKeepsLastOnline() throws {
        let suite = "whitegram-spy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WhitegramSpyStore(accountId: 101, defaults: defaults)
        let dates = Dictionary(uniqueKeysWithValues: (1...2000).map { (String($0), Int32(1700000000 + $0)) })
        let object: [String: Any] = ["version": 1, "accountId": 101, "peers": ["201": ["lastOnline": 1700003000, "readDates": dates]]]
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: store.storageKey)
        try store.record(peerId: 202, messageId: 7, readDate: 1700005000)
        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.values.reduce(0, { $0 + $1.readDates.count }), 2000)
        XCTAssertNil(try store.readDate(peerId: 201, messageId: 1))
        XCTAssertEqual(try store.readDate(peerId: 202, messageId: 7), 1700005000)
        XCTAssertEqual(try store.lastOnline(peerId: 201), 1700003000)
    }
}
