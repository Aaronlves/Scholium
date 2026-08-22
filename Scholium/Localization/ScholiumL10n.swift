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
        static var triptychs: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.triptychs",
                defaultValue: "Triptychs",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for managing registered Triptychs and their folders."
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

        static var hotkeys: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.hotkeys",
                defaultValue: "Hotkeys",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for customizable Scholium keyboard shortcuts."
            )
        }

        static var propertyProfiles: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.propertyProfiles",
                defaultValue: "Metadata Profiles",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for optional Agent-managed fields and About profiles."
            )
        }

        static var researchGuidance: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.researchGuidance",
                defaultValue: "Research Guidance",
                table: "Interface",
                bundle: .module,
                comment: "Settings group for Methods and Practices, Action Profiles, Agent Access, and External Tools and Citations."
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
    }

}
