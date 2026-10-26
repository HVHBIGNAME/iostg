import Foundation
import TelegramCore

public enum WhitegramRemainingInformation {
    public static let informationKeys: [String: String] = [
        "hideChannelAdsInfo": "s.hideChannelAds.desc",
        "hideWhitegramUserBadgeInfo": "s.hideWhitegramUserBadge.desc",
        "hideOthersCustomMessageStyleInfo": "s.hideOthersCustomMsgStyle.desc",
        "iconsInfo": "icons.info"
    ]
    public static let titleKeys: [String: String] = [
        "appBadgeColorIsBlack": "s.appBadgeColor",
        "hideWhitegramUserBadge": "s.hideWhitegramUserBadge",
        "hideOthersCustomMessageStyle": "s.hideOthersCustomMsgStyle",
        "iconPackSitePreview": "s.createIconPack"
    ]
    public static let iconPackSite = "https://whitegram.click"
    public static let iconPackSiteDescriptionKey = "wh.createIconPack"
}
