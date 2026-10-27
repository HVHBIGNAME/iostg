"""Keep upstream module boundaries, with explicit legacy Whitegram storage consumers."""

import re
from pathlib import Path

# These pre-existing adapters consume raw history views/messages or Postbox-backed
# plugin scopes. They are not migrated by the public fork's import-only pass.
POSTBOX_IMPORTERS = (
    "submodules/ChatListUI/Sources/Node/WhitegramLocalPinList.swift",
    "submodules/SettingsUI/Sources/Whitegram/WhitegramPluginTelegram.swift",
    "submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/WhitegramChatOnlineIndicator.swift",
    "submodules/TelegramUI/Sources/WhitegramFeedController.swift",
    "submodules/TelegramUI/Sources/WhitegramFeedLoader.swift",
    "submodules/TelegramUI/Sources/WhitegramLocalNotifications.swift",
    "submodules/TelegramUI/Sources/WhitegramNotificationContent.swift",
    "submodules/TelegramUI/Sources/WhitegramNotificationEnrichment.swift",
    "submodules/TelegramUI/Sources/WhitegramReadActionUI.swift",
)
POSTBOX_ACCESSORS = (
    "submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift",
    "submodules/SettingsUI/Sources/Whitegram/WhitegramPluginRuntime.swift",
    "submodules/SettingsUI/Sources/Whitegram/WhitegramPluginTelegram.swift",
    "submodules/SettingsUI/Sources/WhitegramContentMediaController.swift",
    "submodules/SettingsUI/Sources/WhitegramHistoryController.swift",
    "submodules/SettingsUI/Sources/WhitegramHistoryNativeController.swift",
    "submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift",
    "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift",
    "submodules/TelegramUI/Sources/WhitegramNotificationEnrichment.swift",
)
POSTBOX_PACKAGES = (
    "//submodules/SettingsUI",
    "//submodules/TelegramUI/Components/Chat/ChatMessageItemImpl",
)


def apply_module_boundaries(root: Path, sources: set[str]) -> None:
    """Do not resurrect removed Postbox/TelegramApi imports from public 12.6.2."""
    for filename, additions in (("AllowedImporters.txt", POSTBOX_IMPORTERS), ("AllowedPostboxAccess.txt", POSTBOX_ACCESSORS)):
        path = root / "submodules/Postbox" / filename
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        headers = [line for line in lines if line.startswith("#")]
        note = "# Whitegram legacy storage adapters (telegram_131_boundaries.py)."
        if note not in headers:
            headers.append(note)
        entries = {line for line in lines if line and not line.startswith("#")} | set(additions)
        updated = "\n".join(headers) + "\n\n" + "\n".join(sorted(entries)) + "\n"
        if text != updated:
            path.write_text(updated, encoding="utf-8")
    allowed = set((root / "submodules/Postbox/AllowedImporters.txt").read_text(encoding="utf-8").splitlines())
    for relative in sorted(sources):
        if not relative.endswith(".swift"):
            continue
        path = root / relative
        if not path.is_file() or relative.startswith(("submodules/TelegramCore/", "submodules/Postbox/")):
            continue
        text = path.read_text(encoding="utf-8")
        updated = text.replace("import TelegramApi\n", "")
        if relative not in allowed:
            updated = updated.replace("import Postbox\n", "")
        if updated != text:
            path.write_text(updated, encoding="utf-8")
    path = root / "submodules/Postbox/BUILD"
    text = path.read_text(encoding="utf-8")
    anchor = '    name = "clients",\n    packages = [\n'
    if text.count(anchor) != 1:
        raise ValueError("Postbox client package group changed")
    additions = [package for package in POSTBOX_PACKAGES if f'        "{package}",' not in text]
    if additions:
        path.write_text(text.replace(anchor, anchor + "".join(f'        "{package}",\n' for package in additions)), encoding="utf-8")
    clients = set(re.findall(r'"(//[^"\n]+)"', text.split("swift_library(", 1)[0])) | set(POSTBOX_PACKAGES)
    for build in (root / "submodules").rglob("BUILD"):
        package = "//" + build.parent.relative_to(root).as_posix()
        if package in ("//submodules/Postbox", "//submodules/TelegramCore", "//submodules/TelegramApi"):
            continue
        text = build.read_text(encoding="utf-8")
        forbidden = ("TelegramApi",) if package in clients else ("TelegramApi", "Postbox")
        lines = [line for line in text.splitlines(keepends=True) if not any(line.strip().rstrip(",") in (f'"//submodules/{name}:{name}"', f'"//submodules/{name}"') for name in forbidden)]
        updated = "".join(lines)
        if text != updated:
            build.write_text(updated, encoding="utf-8")
