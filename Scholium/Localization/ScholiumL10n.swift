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

    enum WritingAssistance {
        static var title: LocalizedStringResource {
            LocalizedStringResource("Writing Assistance", table: "Interface", bundle: .module)
        }
        static var enable: LocalizedStringResource {
            LocalizedStringResource("Enable AI Continuation", table: "Interface", bundle: .module)
        }
        static var model: LocalizedStringResource {
            LocalizedStringResource("Continuation Model", table: "Interface", bundle: .module)
        }
        static var openTriptych: LocalizedStringResource {
            LocalizedStringResource(
                "Open a Triptych and connect Codex in Agents & Chat to choose a continuation model.",
                table: "Interface", bundle: .module
            )
        }
        static var connect: LocalizedStringResource {
            LocalizedStringResource(
                "Connect and sign in to Codex in Agents & Chat. Your selected model is retained.",
                table: "Interface", bundle: .module
            )
        }
        static var unavailableModel: LocalizedStringResource {
            LocalizedStringResource(
                "The selected model is unavailable on this connection. Choose an available model; Scholium will not substitute another model automatically.",
                table: "Interface", bundle: .module
            )
        }
        static var contextAndAllowance: LocalizedStringResource {
            LocalizedStringResource(
                "AI continuation uses the connected Codex account and may consume its allowance. Requests use low or lower supported reasoning effort and the standard service tier. Writing context and relevant search excerpts are sent to that connection; processing may be remote. With AI off or unavailable, local terminology completion remains available.",
                table: "Interface", bundle: .module
            )
        }
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
                defaultValue: "Document Appearance",
                table: "Interface",
                bundle: .module,
                comment:
                    "Settings tab for document content presentation and appearance profiles, including typography."
            )
        }

        static var notifications: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.notifications",
                defaultValue: "Notifications & Reminders",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for notification reminders and dismissed items."
            )
        }

    }

}
