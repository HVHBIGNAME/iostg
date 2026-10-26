import Foundation
import CoreFoundation

public enum WhitegramPreferences {
    public static let storageKey = "WhitegramSettingsState.v1"
    public static let updatedNotification = Notification.Name("WhitegramSettingsStateUpdated")
    private static let lock = NSRecursiveLock()
    private static var cachedData: Data?
    private static var cachedLegacyData: Data?
    private static var cachedValues: [String: Any]?
    public static let accountProfilesKey = "WhitegramAccountSettings.v1"
    public enum Scope: Equatable { case shared, account(Int64) }
    private struct Profile: Codable {
        var values: Data
        var mirrors: Data
    }
    private struct Profiles: Codable {
        var version = 1
        var separate: [String: Bool] = [:]
        var accounts: [String: Profile] = [:]
        var sharedMirrors: Data?
        var mirrorKeys: Set<String> = []
    }
    private static var activeAccountId = UserDefaults.standard.object(forKey: "wg_activeWhitegramAccountId").flatMap(exactInteger)
    private static var registeredMirrorKeys = Set<String>()
    private static var cachedProfilesData: Data?
    private static var cachedProfiles: Profiles?
    private static var cachedPrivateData: Data?
    private static var cachedPrivateValues: [String: Any]?

    private static func profileKey(_ key: String) -> Bool {
        return !key.hasPrefix("plugin") && !key.hasPrefix("fork") && !key.hasPrefix("activeWhitegram")
            && !key.hasPrefix("clientInterfaceLocalPremiumAccounts") && !key.hasPrefix("apiSession")
            && !key.hasSuffix("ApiKey") && !key.hasSuffix("ConnectionStatus")
    }

    private static func profiles(_ defaults: UserDefaults) throws -> Profiles {
        let object = defaults.object(forKey: accountProfilesKey)
        if object != nil && !(object is Data) { throw profileError() }
        let data = object as? Data
        if let cachedProfiles, data == cachedProfilesData { return cachedProfiles }
        let result: Profiles
        if let object {
            guard let data = object as? Data, data.count <= 16 * 1024 * 1024 else { throw profileError() }
            result = try PropertyListDecoder().decode(Profiles.self, from: data)
            guard result.version == 1, result.accounts.count <= 1000,
                  result.mirrorKeys.count <= 10000,
                  result.mirrorKeys.allSatisfy({ $0.hasPrefix("wg_") || $0.hasPrefix("WhiteGram") || $0.hasPrefix("whitegram.") }),
                  result.separate.keys.allSatisfy({ Int64($0).map(String.init) == $0 && $0 != "0" }),
                  result.accounts.keys.allSatisfy({ Int64($0).map(String.init) == $0 && $0 != "0" }) else { throw profileError() }
            for profile in result.accounts.values { _ = try decodeProfile(profile) }
            if let mirrors = result.sharedMirrors,
               !(try PropertyListSerialization.propertyList(from: mirrors, format: nil) is [String: Any]) { throw profileError() }
        } else {
            var initial = Profiles()
            if let legacy = defaults.object(forKey: "wg_separateAccountSettings.v1") {
                guard let dictionary = legacy as? [String: Any] else { throw profileError() }
                for (id, value) in dictionary {
                    guard let parsed = Int64(id), parsed != 0, String(parsed) == id,
                          let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw profileError() }
                    initial.separate[id] = number.boolValue
                }
            }
            result = initial
        }
        cachedProfilesData = data
        cachedProfiles = result
        return result
    }

    private static func profileError() -> NSError {
        return NSError(domain: "WhitegramAccountSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "The account settings store is invalid. Saved profiles have not been replaced."])
    }

    private static func decodeProfile(_ profile: Profile) throws -> (values: [String: Any], mirrors: [String: Any]) {
        guard let values = try JSONSerialization.jsonObject(with: profile.values) as? [String: Any],
              let mirrors = try PropertyListSerialization.propertyList(from: profile.mirrors, format: nil) as? [String: Any] else { throw profileError() }
        return (values, mirrors)
    }

    private static func makeProfile(_ values: [String: Any], mirrors: [String: Any]) throws -> Profile {
        guard JSONSerialization.isValidJSONObject(values),
              PropertyListSerialization.propertyList(mirrors, isValidFor: .binary) else { throw profileError() }
        return Profile(values: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
            mirrors: try PropertyListSerialization.data(fromPropertyList: mirrors, format: .binary, options: 0))
    }

    private static func initialProfile(accountId: Int64, values: [String: Any], mirrors: [String: Any], defaults: UserDefaults) throws -> Profile {
        var values = values.filter { profileKey($0.key) }
        var mirrors = mirrors
        let keys = Set(values.keys).union(registeredMirrorKeys.filter { $0.hasPrefix("wg_") }.map { String($0.dropFirst(3)) })
        for key in keys where profileKey(key) {
            if let legacy = defaults.object(forKey: "wg_" + key + "_account_" + String(accountId)) {
                values[key] = legacy
                mirrors["wg_" + key] = legacy
            }
        }
        return try makeProfile(values, mirrors: mirrors)
    }

    private static func scope(_ state: Profiles, accountId: Int64?) -> Scope {
        if let accountId, accountId != 0, state.separate[String(accountId)] == true { return .account(accountId) }
        return .shared
    }

    public static func scope(accountId: Int64) throws -> Scope {
        lock.lock()
        defer { lock.unlock() }
        return scope(try profiles(.standard), accountId: accountId)
    }

    public static func usesSeparateSettings(accountId: Int64) throws -> Bool {
        return try scope(accountId: accountId) != .shared
    }

    public static func registerProfileMirrors(_ keys: Set<String>) {
        lock.lock()
        registeredMirrorKeys.formUnion(keys.filter { !$0.hasPrefix("wg_") || profileKey(String($0.dropFirst(3))) })
        lock.unlock()
    }

    private static func mirrorSnapshot(_ state: Profiles, defaults: UserDefaults) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in state.mirrorKeys.union(registeredMirrorKeys) { result[key] = defaults.object(forKey: key) }
        return result
    }

    private static func snapshot(_ selected: Scope, state: Profiles, defaults: UserDefaults) throws -> (values: [String: Any], mirrors: [String: Any]) {
        let shared = try strictValues(defaults)
        if case let .account(id) = selected {
            guard let profile = state.accounts[String(id)] else { throw profileError() }
            var result = try decodeProfile(profile)
            result.values.merge(shared.filter { !profileKey($0.key) }, uniquingKeysWith: { _, new in new })
            if selected == scope(state, accountId: activeAccountId) {
                result.mirrors = mirrorSnapshot(state, defaults: defaults)
            }
            return result
        }
        let mirrors: [String: Any]
        if scope(state, accountId: activeAccountId) == .shared { mirrors = mirrorSnapshot(state, defaults: defaults) }
        else if let data = state.sharedMirrors {
            guard let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw profileError() }
            mirrors = decoded
        } else { throw profileError() }
        return (shared, mirrors)
    }

    private static func saveProfiles(_ state: Profiles, defaults: UserDefaults) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(state)
        guard data.count <= 16 * 1024 * 1024, state.accounts.count <= 1000, state.separate.count <= 1000 else { throw profileError() }
        defaults.set(data, forKey: accountProfilesKey)
        cachedProfilesData = data
        cachedProfiles = state
    }

    private static func project(_ selected: Scope, state: Profiles, defaults: UserDefaults) throws {
        var current = try snapshot(selected, state: state, defaults: defaults)
        if case let .account(id) = selected, let profile = state.accounts[String(id)] {
            current.mirrors = try decodeProfile(profile).mirrors
        } else if selected == .shared, let data = state.sharedMirrors {
            guard let saved = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw profileError() }
            current.mirrors = saved
        }
        for key in state.mirrorKeys.union(registeredMirrorKeys) { defaults.set(current.mirrors[key], forKey: key) }
        for (key, value) in current.values where profileKey(key) && (value is String || value is NSNumber) {
            defaults.set(value, forKey: "wg_" + key)
        }
    }

    @discardableResult
    public static func activateAccount(_ id: Int64?) -> Bool {
        if id == 0 { return false }
        lock.lock()
        do {
            let defaults = UserDefaults.standard
            var state = try profiles(defaults)
            let previous = scope(state, accountId: activeAccountId)
            state.mirrorKeys.formUnion(registeredMirrorKeys)
            state.mirrorKeys.formUnion(try strictValues(defaults).keys.filter(profileKey).map { "wg_" + $0 })
            if case let .account(old) = previous, state.accounts[String(old)] == nil {
                let shared = try strictValues(defaults).filter { profileKey($0.key) }
                state.accounts[String(old)] = try initialProfile(accountId: old, values: shared, mirrors: mirrorSnapshot(state, defaults: defaults), defaults: defaults)
                state.sharedMirrors = try makeProfile([:], mirrors: Dictionary(uniqueKeysWithValues: shared.compactMap { key, value in
                    value is String || value is NSNumber ? ("wg_" + key, value) : nil
                })).mirrors
            }
            let existing = try snapshot(previous, state: state, defaults: defaults)
            let mirrors = mirrorSnapshot(state, defaults: defaults)
            switch previous {
            case .shared: state.sharedMirrors = try makeProfile([:], mirrors: mirrors).mirrors
            case let .account(old): state.accounts[String(old)] = try makeProfile(existing.values.filter { profileKey($0.key) }, mirrors: mirrors)
            }
            let next = scope(state, accountId: id)
            if case let .account(nextId) = next, state.accounts[String(nextId)] == nil {
                let shared = try snapshot(.shared, state: state, defaults: defaults)
                state.accounts[String(nextId)] = try initialProfile(accountId: nextId, values: shared.values, mirrors: shared.mirrors, defaults: defaults)
            }
            let changed = activeAccountId != id
            try saveProfiles(state, defaults: defaults)
            try project(next, state: state, defaults: defaults)
            activeAccountId = id
            defaults.set(id, forKey: "wg_activeWhitegramAccountId")
            lock.unlock()
            if changed { NotificationCenter.default.post(name: updatedNotification, object: nil) }
            return true
        } catch {
            lock.unlock()
            NSLog("Whitegram: could not switch account settings (%@)", String(describing: type(of: error)))
            return false
        }
    }

    public static func setUsesSeparateSettings(_ enabled: Bool, accountId: Int64) throws {
        guard accountId != 0 else { throw profileError() }
        lock.lock()
        do {
            let defaults = UserDefaults.standard
            var state = try profiles(defaults)
            let previous = scope(state, accountId: activeAccountId)
            state.mirrorKeys.formUnion(registeredMirrorKeys)
            let shared = try strictValues(defaults)
            state.mirrorKeys.formUnion(shared.keys.filter(profileKey).map { "wg_" + $0 })
            let raw = mirrorSnapshot(state, defaults: defaults)
            if previous == .shared { state.sharedMirrors = try makeProfile([:], mirrors: raw).mirrors }
            else if case let .account(id) = previous {
                let old = try snapshot(previous, state: state, defaults: defaults)
                state.accounts[String(id)] = try makeProfile(old.values.filter { profileKey($0.key) }, mirrors: raw)
            }
            if enabled && state.accounts[String(accountId)] == nil {
                let initial = try snapshot(.shared, state: state, defaults: defaults)
                state.accounts[String(accountId)] = try initialProfile(accountId: accountId, values: initial.values, mirrors: initial.mirrors, defaults: defaults)
            }
            state.separate[String(accountId)] = enabled
            try saveProfiles(state, defaults: defaults)
            defaults.set(state.separate, forKey: "wg_separateAccountSettings.v1")
            let next = scope(state, accountId: activeAccountId)
            if next != previous { try project(next, state: state, defaults: defaults) }
        } catch { lock.unlock(); throw error }
        lock.unlock()
        NotificationCenter.default.post(name: updatedNotification, object: nil)
    }

    public static func values() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        do {
            let state = try profiles(defaults)
            let selected = scope(state, accountId: activeAccountId)
            if case let .account(id) = selected {
                guard let profile = state.accounts[String(id)] else { throw profileError() }
                if cachedPrivateData != profile.values || cachedPrivateValues == nil {
                    cachedPrivateValues = dictionary(profile.values)
                    cachedPrivateData = profile.values
                }
                var result = cachedPrivateValues ?? [:]
                result.merge(sharedValues(defaults).filter { !profileKey($0.key) }, uniquingKeysWith: { _, new in new })
                return result
            }
        } catch {
            NSLog("Whitegram: could not read account preferences (%@)", String(describing: type(of: error)))
            return [:]
        }
        return sharedValues(defaults)
    }

    private static func sharedValues(_ defaults: UserDefaults) -> [String: Any] {
        let data = defaults.data(forKey: storageKey)
        let legacyData = defaults.data(forKey: "WhitegramPrivacySettings.v1")
        if let cachedValues, data == cachedData, legacyData == cachedLegacyData {
            return migrateRecoveredValues(cachedValues, defaults: defaults)
        }
        var result = dictionary(data)
        if let legacy = defaults.data(forKey: "WhitegramPrivacySettings.v1") {
            for (key, value) in dictionary(legacy) {
                let canonical = key == "saveDeletedMessages" ? "showDeletedMessages" : key
                if result[canonical] == nil { result[canonical] = value }
            }
        }
        cachedData = data
        cachedLegacyData = legacyData
        cachedValues = result
        return migrateRecoveredValues(result, defaults: defaults)
    }

    private static func dictionary(_ data: Data?) -> [String: Any] {
        guard let data else { return [:] }
        do {
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            NSLog("Whitegram: could not decode saved preferences (%@)", String(describing: type(of: error)))
            return [:]
        }
    }

    public static func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let number = values()[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return defaultValue }
        return number.boolValue
    }

    public static func string(_ key: String, default defaultValue: String = "") -> String {
        return (values()[key] as? String) ?? defaultValue
    }

    public static func number(_ key: String, default defaultValue: Double = 0.0) -> Double {
        guard let number = values()[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return defaultValue }
        return number.doubleValue
    }

    static func exactInteger(_ value: Any) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        if let integer = Int64(number.stringValue) { return integer }
        let decimal = number.decimalValue
        guard decimal >= Decimal(Int64.min), decimal <= Decimal(Int64.max) else { return nil }
        let integer = NSDecimalNumber(decimal: decimal).int64Value
        return Decimal(integer) == decimal ? integer : nil
    }

    private static func migrateRecoveredValues(_ values: [String: Any], defaults: UserDefaults) -> [String: Any] {
        var result = values
        if let old = values["localStarsCount"] as? NSNumber, CFGetTypeID(old) == CFBooleanGetTypeID() {
            let mirrored = defaults.object(forKey: "wg_localStarsCount").flatMap(exactInteger)
            result["localStarsCount"] = mirrored.flatMap { $0 > 0 ? $0 : nil } ?? Int64(9999)
        }
        let accountKey = "activeWhitegramAccountId"
        if let stored = values[accountKey] {
            if let exact = exactInteger(stored) {
                result[accountKey] = exact
            } else if let old = stored as? NSNumber, CFGetTypeID(old) == CFBooleanGetTypeID() {
                result[accountKey] = defaults.object(forKey: "wg_" + accountKey).flatMap(exactInteger)
            } else {
                result.removeValue(forKey: accountKey)
            }
        } else {
            result[accountKey] = defaults.object(forKey: "wg_" + accountKey).flatMap(exactInteger)
        }
        return result
    }

    private static func strictValues(_ defaults: UserDefaults) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for key in ["WhitegramPrivacySettings.v1", storageKey] {
            guard let object = defaults.object(forKey: key) else { continue }
            guard let data = object as? Data,
                  let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "WhitegramPreferences", code: 1, userInfo: [NSLocalizedDescriptionKey: "The saved settings store is invalid. It has not been replaced."])
            }
            for (name, value) in dictionary {
                let name = key == "WhitegramPrivacySettings.v1" && name == "saveDeletedMessages" ? "showDeletedMessages" : name
                result[name] = value
            }
        }
        return migrateRecoveredValues(result, defaults: defaults)
    }

    static func readProfileForTransfer<T>(scope selected: Scope?, _ read: ([String: Any], [String: Any]) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        let state = try profiles(.standard)
        let current = try snapshot(selected ?? scope(state, accountId: activeAccountId), state: state, defaults: .standard)
        return try read(current.values, current.mirrors)
    }

    private static func commit(_ changes: [String: Any], mirrors supplied: [String: Any], selected: Scope, state: inout Profiles, defaults: UserDefaults) throws -> Bool {
        var current = try snapshot(selected, state: state, defaults: defaults)
        let before = try makeProfile(current.values, mirrors: current.mirrors)
        current.values.merge(changes, uniquingKeysWith: { _, new in new })
        current.mirrors.merge(supplied, uniquingKeysWith: { _, new in new })
        for (key, value) in changes where profileKey(key) && (value is String || value is NSNumber) {
            current.mirrors["wg_" + key] = value
        }
        state.mirrorKeys.formUnion(current.mirrors.keys)
        let updated = try makeProfile(current.values, mirrors: current.mirrors)
        var shared = try strictValues(defaults)
        switch selected {
        case .shared:
            shared = current.values
            state.sharedMirrors = updated.mirrors
        case let .account(id):
            state.accounts[String(id)] = try makeProfile(current.values.filter { profileKey($0.key) }, mirrors: current.mirrors)
            shared.merge(changes.filter { !profileKey($0.key) }, uniquingKeysWith: { _, new in new })
        }
        let sharedData = try JSONSerialization.data(withJSONObject: shared, options: [.sortedKeys])
        try saveProfiles(state, defaults: defaults)
        defaults.set(sharedData, forKey: storageKey)
        cachedData = sharedData
        cachedLegacyData = defaults.data(forKey: "WhitegramPrivacySettings.v1")
        cachedValues = shared
        let active = scope(state, accountId: activeAccountId)
        if active == selected {
            for key in state.mirrorKeys { defaults.set(current.mirrors[key], forKey: key) }
        }
        for (key, value) in changes where !profileKey(key) && (value is String || value is NSNumber) { defaults.set(value, forKey: "wg_" + key) }
        return before.values != updated.values || before.mirrors != updated.mirrors
    }

    static func updateProfileForTransfer<T>(scope selected: Scope?, _ prepare: ([String: Any], [String: Any]) throws -> (result: T, changes: [String: Any], mirrors: [String: Any], notifications: [Notification.Name])) throws -> T {
        lock.lock()
        let result: T
        let notifications: [Notification.Name]
        do {
            var state = try profiles(.standard)
            let selected = selected ?? scope(state, accountId: activeAccountId)
            let current = try snapshot(selected, state: state, defaults: .standard)
            let prepared = try prepare(current.values, current.mirrors)
            let changed = try commit(prepared.changes, mirrors: prepared.mirrors, selected: selected, state: &state, defaults: .standard)
            result = prepared.result
            notifications = changed ? [updatedNotification] + (selected == scope(state, accountId: activeAccountId) ? prepared.notifications : []) : []
        } catch { lock.unlock(); throw error }
        lock.unlock()
        for name in Set(notifications) { NotificationCenter.default.post(name: name, object: nil) }
        return result
    }

    /// Prepares every derived value before committing one canonical JSON snapshot.
    /// Observers run after the lock is released and all derived mirrors are written.
    static func updateForTransfer<T>(_ prepare: (UserDefaults, [String: Any]) throws -> (result: T, changes: [String: Any], mirrors: [String: Any], notifications: [Notification.Name])) throws -> T {
        return try updateProfileForTransfer(scope: nil) { values, _ in try prepare(.standard, values) }
    }

    @discardableResult
    public static func set(_ value: Any, for key: String) -> Bool {
        return update([key: value])
    }

    @discardableResult
    public static func update(_ changes: [String: Any]) -> Bool {
        do {
            return try updateProfileForTransfer(scope: nil) { _, _ in (true, changes, [:], []) }
        } catch {
            NSLog("Whitegram: could not encode preferences (%@)", String(describing: type(of: error)))
            return false
        }
    }

    public static func load<T: Codable>(defaults value: T) -> T {
        do {
            let encoded = try JSONEncoder().encode(value)
            var merged = dictionary(encoded)
            let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: value).children.compactMap { child -> (String, Any)? in
                guard let label = child.label else { return nil }
                return (label, child.value)
            })
            for (key, stored) in values() {
                let fallback = merged[key]
                if ["videoBackgroundPath", "profilePhotoWallStatusText", "translationTargetLang"].contains(key) && !(stored is String) { continue }
                if fallback is String && !(stored is String) { continue }
                if fallback is [[String: String]] && !(stored is [[String: String]]) { continue }
                if fallback is [Any] && !(stored is [Any]) { continue }
                if let number = fallback as? NSNumber {
                    guard let storedNumber = stored as? NSNumber else { continue }
                    if (CFGetTypeID(number) == CFBooleanGetTypeID()) != (CFGetTypeID(storedNumber) == CFBooleanGetTypeID()) { continue }
                    if fields[key] is Int || fields[key] is Int64 {
                        guard let integer = exactInteger(storedNumber) else { continue }
                        if fields[key] is Int && Int(exactly: integer) == nil { continue }
                        merged[key] = integer
                        continue
                    }
                }
                merged[key] = stored
            }
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: merged))
        } catch {
            NSLog("Whitegram: could not migrate preference snapshot (%@)", String(describing: type(of: error)))
            return value
        }
    }

    @discardableResult
    public static func save<T: Encodable>(_ value: T) -> Bool {
        do {
            return update(dictionary(try JSONEncoder().encode(value)))
        } catch {
            NSLog("Whitegram: invalid preference value (%@)", String(describing: type(of: error)))
            return false
        }
    }
}
