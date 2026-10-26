import Foundation
import CoreFoundation

public struct WhitegramNavigationPolicy: Equatable {
    public let separateProfileTab: Bool
    public let hideBottomTabBar: Bool

    public init(values: [String: Any]) {
        self.separateProfileTab = Self.flag(values["separateProfileTab"])
        self.hideBottomTabBar = Self.flag(values["hideBottomTabBar"])
    }

    public static func flag(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    public static func selection(previous: String?, available: [String], fallback: String) -> Int? {
        if let previous, let index = available.firstIndex(of: previous) { return index }
        return available.firstIndex(of: fallback) ?? available.indices.first
    }
}

/// Reads the controller's account even when another account is currently foregrounded.
public enum WhitegramNavigationSettings {
    public static func values(accountId: Int64) throws -> [String: Any] {
        let scope = try WhitegramPreferences.scope(accountId: accountId)
        return try WhitegramPreferences.readProfileForTransfer(scope: scope) { values, _ in
            guard try WhitegramPreferences.scope(accountId: accountId) == scope else { throw scopeChanged() }
            return values
        }
    }

    public static func policy(accountId: Int64) throws -> WhitegramNavigationPolicy {
        return WhitegramNavigationPolicy(values: try values(accountId: accountId))
    }

    public static func update(_ changes: [String: Any], accountId: Int64, expectedScope: WhitegramPreferences.Scope? = nil) throws {
        let scope = try WhitegramPreferences.scope(accountId: accountId)
        guard expectedScope == nil || expectedScope == scope else {
            throw scopeChanged()
        }
        try WhitegramPreferences.updateProfileForTransfer(scope: scope) { _, _ in
            guard try WhitegramPreferences.scope(accountId: accountId) == scope else { throw scopeChanged() }
            return ((), changes, [:], [])
        }
    }

    private static func scopeChanged() -> NSError {
        return NSError(domain: "WhitegramNavigation", code: 1, userInfo: [NSLocalizedDescriptionKey: "The account settings scope changed. Please try again."])
    }
}
