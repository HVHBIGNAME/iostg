import Foundation

public enum WhitegramSettingsArchiveStore {
    public static func registerProfileMirrors() {
        WhitegramPreferences.registerProfileMirrors(WhitegramSettingsArchiveMirrors.profileMirrorKeys)
    }

    public static func exportSettings(date: Date = Date(), scope: WhitegramPreferences.Scope? = nil) throws -> WhitegramSettingsArchiveExport {
        registerProfileMirrors()
        return try WhitegramPreferences.readProfileForTransfer(scope: scope) { preferences, mirrors in
            let snapshot = try WhitegramSettingsArchiveMirrors.capture(preferences: preferences, storedValues: mirrors)
            return try WhitegramSettingsArchive.export(values: snapshot, date: date)
        }
    }

    public static func importSettings(_ archive: WhitegramSettingsArchive, scope: WhitegramPreferences.Scope? = nil) throws -> WhitegramSettingsArchiveImportResult {
        // Review may have happened earlier. The transaction reads the latest settings,
        // so absent keys (including privacy flags) are never restored from a stale copy.
        registerProfileMirrors()
        return try WhitegramPreferences.updateProfileForTransfer(scope: scope) { _, mirrors in
            let values = try WhitegramSettingsArchiveSchema.validate(archive.values).values
            let prepared = try WhitegramSettingsArchiveMirrors.prepare(values, storedValues: mirrors)
            let restart = values["compactChatList"] != nil || values["hideBottomTabBar"] != nil
            let result = WhitegramSettingsArchiveImportResult(importedKeys: values.keys.sorted(), restartRecommended: restart)
            return (result, prepared.changes, prepared.mirrors, prepared.notifications)
        }
    }
}
