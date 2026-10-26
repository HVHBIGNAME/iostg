"""Select the Whitegram profile before constructing the primary account UI."""

from client_device_patches import client_device_patches
from client_interface_patches import client_interface_patches
from source_patches import SourcePatches

ACCOUNT_SETTINGS_RUNTIME_FILES = {
    "WhitegramAccountSettingsController.swift": "submodules/SettingsUI/Sources/WhitegramAccountSettingsController.swift",
}


def apply_account_settings_patches(root):
    patches = SourcePatches(root)
    path = "submodules/TelegramUI/Sources/AppDelegate.swift"
    anchor = "            |> map { primary, _, _ -> AccountContext? in\n                return primary\n"
    patches.replace("account-settings-profile", path, anchor, """            |> map { primary, _, _ -> AccountContext? in
                WhitegramSettingsArchiveStore.registerProfileMirrors()
                let whitegramProfileKeys = Mirror(reflecting: WhitegramSettingsState()).children.compactMap { $0.label }.map { "wg_" + $0 }
                WhitegramPreferences.registerProfileMirrors(Set(whitegramProfileKeys).union(["wg_perChatGhost", "wg_musicEqualizerBands", "wg_ghostModeExceptions"]))
                _ = WhitegramPreferences.activateAccount(primary?.account.id.int64)
                return primary
""")
    return patches.write()


def apply_client_settings_patches(root):
    patches = SourcePatches(root)
    client_interface_patches(patches)
    client_device_patches(patches)
    return patches.write()
