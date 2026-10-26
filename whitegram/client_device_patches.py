"""Beta 3.2 initConnection device-model override and cancellable delayed sends.

Register DEVICE_RUNTIME_FILES and apply_client_device_patches in the shared installer.
Capability bindings: chooseCameraBeforeRoundVideo -> itself (media patcher),
deferredMessages -> itself (boolean), fakeDeviceName -> device settings editor.
"""

from pathlib import Path
from source_patches import SourcePatches

DEVICE_RUNTIME_FILES = {
    "WhitegramDeviceSettings.swift": "submodules/TelegramCore/Sources/WhitegramDeviceSettings.swift",
    "WhitegramDeviceDeferredMessages.swift": "submodules/TelegramCore/Sources/WhitegramDeviceDeferredMessages.swift",
    "WhitegramDeviceSettingsController.swift": "submodules/SettingsUI/Sources/WhitegramDeviceSettingsController.swift",
    "WhitegramDeviceDeferredUI.swift": "submodules/TelegramUI/Sources/WhitegramDeviceDeferredUI.swift",
}
REQUEST = "submodules/MtProtoKit/Sources/MTRequestMessageService.m"
CHAT = "submodules/TelegramUI/Sources/ChatController.swift"
LOAD = "submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift"
RECORDING = "submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift"


def _replace(patches, feature, path, before, after, count=1):
    text = patches.read(path)
    if after in text:
        if text.count(after) != count or before in text.replace(after, ""):
            raise ValueError(f"{feature}: {path}: mixed or duplicated consumer")
    elif text.count(before) != count:
        raise ValueError(f"{feature}: {path}: expected {count} anchors, found {text.count(before)}")
    patches.replace(feature, path, before, after, count=count)


def client_device_patches(patches: SourcePatches) -> None:
    # Original MTRequestMessageService 0x4891c..0x489a0, not MTApiEnvironment:
    # evaluate the defaults mirror each time initConnection is serialized.
    before = "        [buffer appendTLString:_apiEnvironment.deviceModel];\n"
    after = '''        id whitegramDeviceObject = [[NSUserDefaults standardUserDefaults] objectForKey:@"wg_fakeDeviceName"];
        NSString *whitegramDeviceName = [whitegramDeviceObject isKindOfClass:[NSString class]] ? whitegramDeviceObject : nil;
        [buffer appendTLString:whitegramDeviceName.length != 0 ? whitegramDeviceName : _apiEnvironment.deviceModel];
'''
    _replace(patches, "fakeDeviceName", REQUEST, before, after)

    before = "            if commit || !isScheduledMessages {\n"
    after = '''            let whitegramDeferredBatch = WhitegramDeviceDeferredMessages.prepare(messages: messages, peerId: peerId, scheduledSubject: isScheduledMessages, committed: commit, postpone: postpone)
            messages = whitegramDeferredBatch.messages
            if commit || !isScheduledMessages {
'''
    _replace(patches, "deferredMessages", CHAT, before, after)
    before = "                |> deliverOnMainQueue).startStandalone(next: { [weak self] _ in\n                    if let strongSelf = self, strongSelf.presentationInterfaceState.subject != .scheduledMessages {\n"
    after = '''                |> deliverOnMainQueue).startStandalone(next: { [weak self] messageIds in
                    if let self { self.whitegramPresentDeferredSend(whitegramDeferredBatch, messageIds: messageIds) }
                    if let strongSelf = self, strongSelf.presentationInterfaceState.subject != .scheduledMessages {
'''
    _replace(patches, "deferredMessages", CHAT, before, after)

    before = "                let transformedMessages = strongSelf.transformEnqueueMessages(messages, silentPosting: effectiveSilentPosting, scheduleTime: scheduleTime, repeatPeriod: repeatPeriod, postpone: postpone)\n"
    after = before.replace("let transformedMessages", "var transformedMessages") + '''                let whitegramDeferredBatch = WhitegramDeviceDeferredMessages.prepare(messages: transformedMessages, peerId: peerId, scheduledSubject: strongSelf.presentationInterfaceState.subject == .scheduledMessages, committed: scheduleTime != nil, postpone: postpone)
                transformedMessages = whitegramDeferredBatch.messages
'''
    _replace(patches, "deferredMessages", LOAD, before, after)

    before = "            let transformedMessages = self.transformEnqueueMessages(messages, silentPosting: effectiveSilentPosting, scheduleTime: scheduleTime, repeatPeriod: repeatPeriod, postpone: postpone)\n"
    _replace(patches, "deferredMessages", RECORDING, before, before.replace("let transformedMessages", "var transformedMessages"))
    before = '''            guard let peerId = self.chatLocation.peerId else {
                return
            }
           \x20
            let _ = ('''
    after = '''            guard let peerId = self.chatLocation.peerId else {
                return
            }
            let whitegramDeferredBatch = WhitegramDeviceDeferredMessages.prepare(messages: transformedMessages, peerId: peerId, scheduledSubject: self.presentationInterfaceState.subject == .scheduledMessages, committed: scheduleTime != nil, postpone: postpone)
            transformedMessages = whitegramDeferredBatch.messages
           \x20
            let _ = ('''
    _replace(patches, "deferredMessages", RECORDING, before, after)
    before = "            |> deliverOnMainQueue).startStandalone(next: { [weak self] _ in\n                if let strongSelf = self, strongSelf.presentationInterfaceState.subject != .scheduledMessages {\n"
    after = '''            |> deliverOnMainQueue).startStandalone(next: { [weak self] messageIds in
                if let self { self.whitegramPresentDeferredSend(whitegramDeferredBatch, messageIds: messageIds) }
                if let strongSelf = self, strongSelf.presentationInterfaceState.subject != .scheduledMessages {
'''
    _replace(patches, "deferredMessages", RECORDING, before, after)

    before = "            if self.context.engine.messages.enqueueOutgoingMessageWithChatContextResult(to: peerId, threadId: self.chatLocation.threadId, botId: results.botId, result: result, replyToMessageId: replyMessageSubject?.subjectModel, hideVia: hideVia, silentPosting: silentPosting, scheduleTime: scheduleTime, sendPaidMessageStars: sendPaidMessageStars, postpone: postpone) {\n"
    after = '''            if let message = self.context.engine.messages.outgoingMessageWithChatContextResult(to: peerId, threadId: self.chatLocation.threadId, botId: results.botId, result: result, replyToMessageId: replyMessageSubject?.subjectModel, replyToStoryId: nil, hideVia: hideVia, silentPosting: silentPosting, scheduleTime: scheduleTime, sendPaidMessageStars: sendPaidMessageStars, postpone: postpone, correlationId: nil) {
                let whitegramDeferredBatch = WhitegramDeviceDeferredMessages.prepare(messages: [message], peerId: peerId, scheduledSubject: isScheduledMessages, committed: scheduleTime != nil, postpone: postpone)
                let _ = (enqueueMessages(account: self.context.account, peerId: peerId, messages: whitegramDeferredBatch.messages)
                |> deliverOnMainQueue).startStandalone(next: { [weak self] ids in
                    self?.whitegramPresentDeferredSend(whitegramDeferredBatch, messageIds: ids)
                })
'''
    _replace(patches, "deferredMessages", CHAT, before, after)
    before = "                    |> deliverOnMainQueue).startStandalone(next: { messageIds in\n                        guard let strongSelf = self else {\n                            return\n                        }\n"
    after = before + "                        strongSelf.whitegramPresentDeferredSend(whitegramDeferredBatch, messageIds: messageIds)\n"
    _replace(patches, "deferredMessages", LOAD, before, after)


def apply_client_device_patches(root: Path) -> dict[str, list[str]]:
    patches = SourcePatches(root)
    client_device_patches(patches)
    return patches.write()
