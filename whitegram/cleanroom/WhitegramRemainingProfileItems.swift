import Foundation
import TelegramCore
import TelegramPresentationData
import SettingsUI

final class WhitegramRemainingScammerObserver {
    private var observers: [NSObjectProtocol] = []
    init(updated: @escaping () -> Void) {
        for name in [WhitegramPreferences.updatedNotification, UserDefaults.didChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                DispatchQueue.main.async(execute: updated)
            })
        }
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}

func whitegramRemainingScammerItem(data: PeerInfoScreenData, presentationData: PresentationData, interaction: PeerInfoInteraction) -> PeerInfoScreenItem? {
    guard WhitegramPreferences.bool("scammerProtection"), case let .user(user) = data.peer,
          user.id.namespace == Namespaces.Peer.CloudUser,
          case let .listed(savedAt) = whitegramScammerAssessment(userId: user.id.id._internalGetInt64Value()) else { return nil }
    let language = presentationData.strings.baseLanguageCode
    let warning = WhitegramLocalization.string("profile.scammerWarningText", baseLanguage: language)
    let provenance: String
    if let savedAt {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        provenance = "Whitegram · Saved list: " + formatter.string(from: savedAt)
    } else {
        provenance = "Whitegram · Saved list · Date unavailable"
    }
    return PeerInfoScreenLabeledValueItem(id: "whitegram.remaining.scammer", label: WhitegramLocalization.string("profile.scammerWarningLabel", baseLanguage: language),
        text: warning + "\n" + provenance, action: nil, requestLayout: { interaction.requestLayout($0) })
}
