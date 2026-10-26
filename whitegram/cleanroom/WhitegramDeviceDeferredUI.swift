import Foundation
import SwiftSignalKit
import TelegramCore
import UndoUI

extension ChatControllerImpl {
    func whitegramPresentDeferredSend(_ batch: WhitegramDeviceDeferredMessages.Batch, messageIds: [EngineMessage.Id?]) {
        guard let state = batch.state, messageIds.contains(where: { $0 != nil }) else { return }
        let remaining = Double(state.deadline) - Date().timeIntervalSince1970
        guard remaining > 0 else { return }
        let account = self.context.account
        let text = WhitegramLocalization.string("wh.deferredMessages", baseLanguage: self.presentationData.strings.baseLanguageCode)
        self.present(UndoOverlayController(presentationData: self.presentationData,
            content: .info(title: nil, text: text, timeout: remaining, customUndoText: self.presentationData.strings.Common_Cancel), elevatedLayout: false,
            action: { action in
                if case .undo = action {
                    let _ = WhitegramDeviceDeferredMessages.cancel(batch: batch, account: account, messageIds: messageIds).startStandalone()
                    return true
                }
                return false
            }), in: .current)
    }
}
