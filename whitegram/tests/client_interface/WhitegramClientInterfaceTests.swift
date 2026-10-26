import Foundation

@main
enum WhitegramClientInterfaceTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label)
            checks += 1
        }
        let empty = WhitegramClientInterfacePolicy(values: [:])
        check(!empty.cards && !empty.updatedHeader && !empty.oled && !empty.reactionGlow && !empty.accountStrip, "disabled defaults")
        for updated in [false, true] {
            for classic in [false, true] {
                let policy = WhitegramClientInterfacePolicy(values: ["newChatHeaderStyle": updated, "classicInterface": classic])
                check(policy.headerWithoutGlass == (updated || classic), "original OR header gate")
            }
        }
        let malformed = WhitegramClientInterfacePolicy(values: ["newChatListUI": 1, "oledMode": "true", "reactionButtonGlow": NSNull()])
        check(!malformed.cards && !malformed.oled && !malformed.reactionGlow, "strict flag typing")
        let cards = WhitegramClientInterfacePolicy(values: ["newChatListUI": true, "reactionButtonGlow": true])
        check(cards.cardFrame(width: 390, height: 82, leftInset: 0, rightInset: 0) == CGRect(x: 8, y: 3, width: 374, height: 76), "cards geometry")
        check(cards.cardFrame(width: 390, height: 82, leftInset: 44, rightInset: 44).width == 286, "safe areas")
        check(cards.cardFrame(width: 5, height: 2, leftInset: 0, rightInset: 0).size == .zero, "small card bounds")
        check(cards.glowOpacity(isTag: true) == 0 && cards.glowOpacity(isTag: false) == 0.62, "original glow opacity; tags never glow")
        check(empty.glowOpacity(isTag: false) == 0, "disabled glow resets")
        check(WhitegramLocalPremiumPolicy.parseInteger("9223372036854775807", maximum: Int64.max) == Int64.max, "exact emoji Int64")
        for invalid in ["9223372036854775808", "-1", "1.0", "1e3", "true", "", "+2"] {
            check(WhitegramLocalPremiumPolicy.parseInteger(invalid, maximum: Int64.max) == nil, "bad input \(invalid)")
        }
        check(WhitegramLocalPremiumPolicy.decode(["nameColor": false]) == nil, "bool is not color")
        check(WhitegramLocalPremiumPolicy.decode(["profileColor": Int64(Int32.max) + 1]) == nil, "color overflow")
        check(WhitegramLocalPremiumPolicy.decode(["emojiStatus": 0]) == nil, "zero is not emoji ID")
        let policy = WhitegramLocalPremiumPolicy(nameColor: 0, nameBackgroundEmoji: 99, profileColor: 6, profileBackgroundEmoji: 100, emojiStatus: Int64.max)
        check(WhitegramLocalPremiumPolicy.decode(policy.values) == policy, "five-field roundtrip")
        check(WhitegramLocalPremiumPolicy.decode([:]) == WhitegramLocalPremiumPolicy(), "clear returns original presentation")
        let encoded = try! JSONEncoder().encode(policy)
        check(try! JSONDecoder().decode(WhitegramLocalPremiumPolicy.self, from: encoded) == policy, "persistence roundtrip")
        check(WhitegramAccountStripOrder.moving(3, before: 1, snapshot: [1, 2, 3], live: [3, 2, 1]) == [3, 1, 2], "drag preserves live members")
        check(WhitegramAccountStripOrder.moving(2, before: 3, snapshot: [1, 2, 3], live: [1, 2, 4]) == nil, "account removed during drag")
        check(WhitegramAccountStripOrder.moving(2, before: 3, snapshot: [1, 2, 3], live: [1, 2, 3, 4]) == nil, "account added during drag")
        check(WhitegramAccountStripOrder.moving(1, before: 1, snapshot: [1, 2], live: [1, 2]) == nil, "self drag")
        check(WhitegramAccountStripOrder.moving(2, before: 3, snapshot: [2, 2, 3], live: [2, 3]) == nil, "duplicate rejected")
        print("Whitegram client interface: \(checks) runtime checks passed")
    }
}
