import Foundation
import Display
import TelegramCore

@main
enum ClassicProfiles {
    static func main() throws {
        precondition(WhitegramPreferences.activateAccount(nil))
        precondition(WhitegramPreferences.set(false, for: "classicInterface"))
        WhitegramClassicSettings.install()
        precondition(!WhitegramClassicStyle.enabled)
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: 710001)
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: 710002)
        precondition(WhitegramPreferences.activateAccount(710001))
        precondition(WhitegramPreferences.set(true, for: "classicInterface"))
        precondition(WhitegramClassicStyle.enabled)
        precondition(WhitegramPreferences.activateAccount(710002))
        precondition(!WhitegramClassicStyle.enabled)
        precondition(WhitegramPreferences.activateAccount(710001))
        precondition(WhitegramClassicStyle.enabled)
        try WhitegramPreferences.setUsesSeparateSettings(false, accountId: 710001)
        precondition(!WhitegramClassicStyle.enabled)
        try WhitegramPreferences.setUsesSeparateSettings(true, accountId: 710001)
        precondition(WhitegramClassicStyle.enabled)
        print("Classic relay: active-account switching and shared/private profile transitions passed")
    }
}
