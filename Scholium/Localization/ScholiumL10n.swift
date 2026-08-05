import Foundation
import ScholiumContracts
/// Application-owned interface language.
///
/// Researcher-authored prose, quotations, citations, note titles, paths, and
/// imported source text must bypass this namespace and remain verbatim. Purely
/// internal identifiers never enter a catalog, and researcher-owned Method or
/// Practice text remains verbatim at its presentation sites.
enum ScholiumL10n {
    /// Resolves application-authored interface copy from the app resource
    /// bundle. Do not pass researcher-authored or imported text here.
    static func string(
        _ keyAndValue: String.LocalizationValue,
        locale: Locale = .current
    ) -> String {
        String(
            localized: LocalizedStringResource(
                keyAndValue,
                table: "Localizable",
                locale: locale,
                bundle: .module
            )
        )
    }

    /// Resolves application-owned copy carried through a `String`
    /// component boundary. Callers must not use this for document content.
    static func dynamicString(_ keyAndValue: String) -> String {
        Bundle.module.localizedString(
            forKey: keyAndValue,
            value: keyAndValue,
            table: "Localizable"
        )
    }

    static func localized(
        _ resource: LocalizedStringResource,
        locale: Locale = .current
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    enum Settings {
        static var vaults: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.vaults",
                defaultValue: "Vaults",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for configuring the three research vaults."
            )
        }

        static var appearance: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.appearance",
                defaultValue: "Appearance",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for named document appearance profiles and advanced CSS."
            )
        }

        static var properties: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.properties",
                defaultValue: "Properties",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for configured note properties."
            )
        }

        static var researchGuidance: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.researchGuidance",
                defaultValue: "Research Guidance",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for prompts, skills, and research methods."
            )
        }

        static var attention: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.attention",
                defaultValue: "Attention",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for derived attention reminders."
            )
        }

        static var zotero: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.zotero",
                defaultValue: "Zotero",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for the Zotero integration. Do not translate the brand name."
            )
        }
    }

}
