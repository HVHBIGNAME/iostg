import Foundation
import CoreFoundation

public struct WhitegramClientInterfacePolicy: Equatable {
    public let cards: Bool
    public let updatedHeader: Bool
    public let classic: Bool
    public let oled: Bool
    public let reactionGlow: Bool
    public let accountStrip: Bool

    public init(values: [String: Any]) {
        func flag(_ key: String) -> Bool {
            guard let number = values[key] as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            return number.boolValue
        }
        self.cards = flag("newChatListUI")
        self.updatedHeader = flag("newChatHeaderStyle")
        self.classic = flag("classicInterface")
        self.oled = flag("oledMode")
        self.reactionGlow = flag("reactionButtonGlow")
        self.accountStrip = flag("roundProfileButtons")
    }

    // The original header gate at UI:0x183e48..0x183e60 is an OR.
    public var headerWithoutGlass: Bool { return self.updatedHeader || self.classic }

    public func cardFrame(width: Double, height: Double, leftInset: Double, rightInset: Double) -> CGRect {
        guard self.cards else { return CGRect(x: 0, y: 0, width: width, height: height) }
        let x = max(0, leftInset) + 8
        return CGRect(x: x, y: 3, width: max(0, width - x - max(0, rightInset) - 8), height: max(0, height - 6))
    }

    public func glowOpacity(isTag: Bool) -> Float {
        return self.reactionGlow && !isTag ? 0.62 : 0
    }
}
