import Foundation
import ScholiumContracts

/// Application-owned interface language.
///
/// Researcher-authored prose, quotations, citations, note titles, paths, and
/// imported source text must bypass this namespace and remain verbatim. Purely
/// internal identifiers never enter a catalog, and Skill package names and
/// package-authored descriptions remain verbatim at their presentation sites.
enum ScholiumL10n {
    /// Resolves application-authored interface copy from the package resource
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

        static var documentStyles: LocalizedStringResource {
            LocalizedStringResource(
                "settings.tab.documentStyles",
                defaultValue: "Document Styles",
                table: "Interface",
                bundle: .module,
                comment: "Settings tab for document appearance and CSS snippets."
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

    enum ResearchFunction {
        static var dialogueTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.dialogue.title",
                defaultValue: "Dialogue",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for scholarly conversation about a note."
            )
        }

        static var developTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.develop.title",
                defaultValue: "Develop",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for developing an Analysis or Topic."
            )
        }

        static var reviewTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.review.title",
                defaultValue: "Review",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for human review and qualification."
            )
        }

        static var fidelityTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.fidelity.title",
                defaultValue: "Fidelity",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for checking source and citation fidelity."
            )
        }

        static var critiqueTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.critique.title",
                defaultValue: "Critique",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for attributed critique of a Work."
            )
        }

        static var reviseTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.revise.title",
                defaultValue: "Revise",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for substantive revision of a Work."
            )
        }

        static var manuscriptTitle: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.manuscript.title",
                defaultValue: "Manuscript",
                table: "Interface",
                bundle: .module,
                comment: "Research Function name for coordinating manuscript work."
            )
        }

        static var dialogueHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.dialogue.help",
                defaultValue: "Open a scholarly Dialogue for this note",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Dialogue Research Function."
            )
        }

        static var developHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.develop.help",
                defaultValue: "Develop this Analysis or Topic",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Develop Research Function."
            )
        }

        static var reviewHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.review.help",
                defaultValue: "Review and qualify this Analysis or Topic",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Review Research Function."
            )
        }

        static var fidelityHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.fidelity.help",
                defaultValue: "Check philosophical content and citations",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Fidelity Research Function."
            )
        }

        static var critiqueHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.critique.help",
                defaultValue: "Request an attributed Critique of this Work",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Critique Research Function."
            )
        }

        static var reviseHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.revise.help",
                defaultValue: "Prepare a substantive revision of this Work",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Revise Research Function."
            )
        }

        static var manuscriptHelp: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.manuscript.help",
                defaultValue: "Coordinate work on this manuscript",
                table: "Interface",
                bundle: .module,
                comment: "Help and accessibility hint for the Manuscript Research Function."
            )
        }

        static var groupAccessibilityLabel: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.group.accessibilityLabel",
                defaultValue: "Research functions",
                table: "Interface",
                bundle: .module,
                comment: "VoiceOver label for the complete Research Function strip."
            )
        }

        static var openAccessibilityValue: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.state.open",
                defaultValue: "Open",
                table: "Interface",
                bundle: .module,
                comment: "VoiceOver value when a Research Function panel is open."
            )
        }

        static var closedAccessibilityValue: LocalizedStringResource {
            LocalizedStringResource(
                "researchFunction.state.closed",
                defaultValue: "Closed",
                table: "Interface",
                bundle: .module,
                comment: "VoiceOver value when a Research Function panel is closed."
            )
        }
    }
}

extension ResearchFunctionID {
    var interfaceTitleResource: LocalizedStringResource {
        switch self {
        case .dialogue: ScholiumL10n.ResearchFunction.dialogueTitle
        case .develop: ScholiumL10n.ResearchFunction.developTitle
        case .review: ScholiumL10n.ResearchFunction.reviewTitle
        case .fidelity: ScholiumL10n.ResearchFunction.fidelityTitle
        case .critique: ScholiumL10n.ResearchFunction.critiqueTitle
        case .revise: ScholiumL10n.ResearchFunction.reviseTitle
        case .manuscript: ScholiumL10n.ResearchFunction.manuscriptTitle
        }
    }

    var interfaceTitle: String {
        ScholiumL10n.localized(interfaceTitleResource)
    }

    func interfaceTitle(locale: Locale) -> String {
        ScholiumL10n.localized(interfaceTitleResource, locale: locale)
    }

    var interfaceHelpResource: LocalizedStringResource {
        switch self {
        case .dialogue: ScholiumL10n.ResearchFunction.dialogueHelp
        case .develop: ScholiumL10n.ResearchFunction.developHelp
        case .review: ScholiumL10n.ResearchFunction.reviewHelp
        case .fidelity: ScholiumL10n.ResearchFunction.fidelityHelp
        case .critique: ScholiumL10n.ResearchFunction.critiqueHelp
        case .revise: ScholiumL10n.ResearchFunction.reviseHelp
        case .manuscript: ScholiumL10n.ResearchFunction.manuscriptHelp
        }
    }

    var interfaceHelp: String {
        ScholiumL10n.localized(interfaceHelpResource)
    }

    func interfaceHelp(locale: Locale) -> String {
        ScholiumL10n.localized(interfaceHelpResource, locale: locale)
    }
}
