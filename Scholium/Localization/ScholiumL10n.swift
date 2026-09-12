import Foundation
import ScholiumContracts

/// Application-owned interface language.
///
/// Researcher-authored prose, quotations, citations, note titles, paths, and
/// imported source text must bypass this namespace and remain verbatim. Purely
/// internal identifiers never enter a catalog, and researcher-owned Skills or
/// researcher-authored philosophical method and reference text remains verbatim at its presentation sites.
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
        static var workspace: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.workspace",
                defaultValue: "Workspace",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for local Triptych registration and folder access."
            )
        }

        static var document: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.document",
                defaultValue: "Appearance",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for document content presentation and appearance profiles, including typography."
            )
        }

        static var notifications: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.notifications",
                defaultValue: "Notifications",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for notification reminders and dismissed items."
            )
        }

        static var interaction: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.interaction",
                defaultValue: "Interaction",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for keyboard shortcuts and selection actions."
            )
        }

        static var integrations: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.integrations",
                defaultValue: "Integrations",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for Agents, Chat and Zotero integrations."
            )
        }
    }

}
