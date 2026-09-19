import Foundation

// AyuGram: Telegram renders no usable preview for a few sites (x.com and Reddit above all), because those
// sites serve no Open Graph markup to Telegram's crawler. The preview is therefore requested for a mirror
// host that does serve it.
//
// Only the preview request is rewritten. The message text keeps the address the user typed, and the preview
// reports the original address as its source url, so the composer still matches the preview to the link in
// the text. The mirror does end up in the webpage attached to the sent message -- that is the point of the
// feature: the other side gets a preview that actually shows something.
func ayuBetterLinkPreviewUrl(_ url: String, settings: AyuSettings) -> String {
    if !settings.improveLinkPreviews {
        return url
    }
    guard var components = URLComponents(string: url), let host = components.host?.lowercased() else {
        return url
    }

    let mirrorHost: String
    switch host {
    case "twitter.com", "www.twitter.com", "mobile.twitter.com", "x.com", "www.x.com", "mobile.x.com":
        mirrorHost = "fixupx.com"
    case "reddit.com", "www.reddit.com":
        mirrorHost = "vxreddit.com"
    case "instagram.com", "www.instagram.com":
        mirrorHost = "kkclip.com"
    case "pixiv.net", "www.pixiv.net":
        mirrorHost = "phixiv.net"
    default:
        // Short links keep their subdomain: vm.tiktok.com -> vm.kktiktok.com
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            mirrorHost = host.replacingOccurrences(of: "tiktok.com", with: "kktiktok.com")
        } else {
            return url
        }
    }

    components.host = mirrorHost
    return components.string ?? url
}
