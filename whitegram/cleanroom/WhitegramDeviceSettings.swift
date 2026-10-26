import Foundation
import CoreFoundation

public struct WhitegramDeviceSettings: Equatable {
    public let fakeDeviceName: String
    public let deferredMessages: Bool

    public init(values: [String: Any], legacyDefaults: UserDefaults? = nil) {
        let name = values["fakeDeviceName"] ?? legacyDefaults?.object(forKey: "wg_fakeDeviceName")
        self.fakeDeviceName = (name as? String) ?? ""
        let deferred = values["deferredMessages"] ?? legacyDefaults?.object(forKey: "wg_deferredMessages")
        if let number = deferred as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            self.deferredMessages = number.boolValue
        } else {
            self.deferredMessages = false
        }
    }

    public static var current: Self {
        return Self(values: WhitegramPreferences.values(), legacyDefaults: .standard)
    }

    public static func normalizedDeviceName(_ text: String) -> String {
        // Original TelegramUI 0x1106254: normalization belongs to the editor.
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func connectionDeviceModel(fallback: String) -> String {
        return self.fakeDeviceName.isEmpty ? fallback : self.fakeDeviceName
    }

    public static let deferredSeconds: Int32 = 12

    public func deferredDeadline(now: Double, cloudPeer: Bool, scheduledSubject: Bool, committed: Bool, postpone: Bool, hasSchedule: Bool, viewOnce: Bool, paid: Bool) -> Int32? {
        guard self.deferredMessages, cloudPeer, !scheduledSubject, !committed, !postpone, !hasSchedule, !viewOnce, !paid,
              now.isFinite, now >= 0, now < Double(Int32.max - Self.deferredSeconds),
              let timestamp = Int32(exactly: now.rounded(.towardZero)) else { return nil }
        return timestamp + Self.deferredSeconds
    }
}

/// Resolves one batch's undo exactly once; late undo cannot delete a sent message.
public final class WhitegramDeviceDeferredState {
    private let lock = NSLock()
    public let deadline: Int32
    private var resolved = false

    public init(deadline: Int32) { self.deadline = deadline }

    @discardableResult public func cancel(now: Double) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.resolved, now.isFinite, now < Double(self.deadline) else { return false }
        self.resolved = true
        return true
    }
}
