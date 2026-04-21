import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Centralises the knobs that control how session data is grouped inside the S3
/// bucket. Changing `campaign` or the sanitisation rules here is the only thing
/// required to pivot to a new collection campaign.
enum CampaignConfig {
    /// Current campaign tag. When you start a new campaign, bump this value,
    /// rebuild, and new sessions will start landing under the new prefix.
    static let campaign = "EgoTeste-iOS"

    /// UserDefaults key backing the contributor name field in Settings.
    static let userNameStorageKey = "user_name"

    /// UserDefaults key backing the contributor country field in Settings.
    /// Same key `@AppStorage("country")` uses in ``SettingsView``.
    static let countryStorageKey = "country"

    /// Raw contributor name as typed by the user. Empty if never set.
    static var userName: String {
        let raw = UserDefaults.standard.string(forKey: userNameStorageKey) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Two-letter ISO region code for the contributor, uppercased.
    ///
    /// Resolution order:
    /// 1. Value typed in Settings (trimmed + uppercased, first two chars).
    /// 2. Device locale region (`Locale.current.region`).
    /// 3. `"XX"` as a last-resort sentinel so the S3 key never collapses to
    ///    a double slash or an empty path component.
    static var countryCode: String {
        let raw = UserDefaults.standard.string(forKey: countryStorageKey) ?? ""
        let fromSettings = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if fromSettings.count >= 2 {
            return String(fromSettings.prefix(2))
        }
        if let region = Locale.current.region?.identifier, region.count >= 2 {
            return String(region.prefix(2)).uppercased()
        }
        return "XX"
    }

    /// Stable per-device identifier. Survives reinstalls as long as at least one
    /// of our apps remains installed on the device. Used to disambiguate two
    /// contributors who happen to type the same name.
    static var vendorIdentifier: String {
#if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? "no-vendor-id"
#else
        return "no-vendor-id"
#endif
    }

    /// URL-safe slug for the contributor name. Falls back to a stable token
    /// derived from the vendor ID when the field is blank, so a session never
    /// lands under a literal "unknown/".
    static var userSlug: String {
        let slug = slugify(userName)
        if !slug.isEmpty { return slug }
        let tail = vendorIdentifier
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .suffix(6)
        return "anon-\(tail)"
    }

    /// S3 key prefix (without trailing slash) that groups every session
    /// produced by this contributor under this campaign. The country code
    /// sits between the campaign and the user slug so we can partition
    /// uploads by region without touching each contributor's folder
    /// structure. Example: `"EgoTeste-iOS/BR/marcos-d"`.
    static var s3Prefix: String {
        "\(campaign)/\(countryCode)/\(userSlug)"
    }

    /// Lower-cases, strips diacritics, and collapses non-alphanumerics into
    /// single hyphens. Capped at 40 chars so S3 keys stay readable.
    static func slugify(_ input: String) -> String {
        let folded = input
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()

        var out = ""
        var pendingHyphen = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen && !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }

        if out.count > 40 {
            out = String(out.prefix(40))
            while out.hasSuffix("-") { out.removeLast() }
        }
        return out
    }
}
