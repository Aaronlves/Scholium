import Foundation

public enum SearchCapabilityValueKind: String, Codable, Hashable, Sendable {
    case lexical
    case canonical
    case property
    case noteIdentity
}

public struct SearchFieldCapability: Codable, Hashable, Sendable {
    public let name: String
    public let valueKind: SearchCapabilityValueKind
    public let allowedValues: [String]
    public let allowsPhrase: Bool
    public let allowsPrefix: Bool
    public let allowsExclusion: Bool

    public init(
        name: String,
        valueKind: SearchCapabilityValueKind,
        allowedValues: [String] = [],
        allowsPhrase: Bool,
        allowsPrefix: Bool,
        allowsExclusion: Bool
    ) {
        self.name = name
        self.valueKind = valueKind
        self.allowedValues = allowedValues
        self.allowsPhrase = allowsPhrase
        self.allowsPrefix = allowsPrefix
        self.allowsExclusion = allowsExclusion
    }
}

public struct SearchProviderCapability: Codable, Hashable, Sendable {
    public let provider: SearchProvider
    public let fields: [SearchFieldCapability]
    public let scopes: [SearchPresentationScope]
    public let examples: [String]

    public init(
        provider: SearchProvider,
        fields: [SearchFieldCapability],
        scopes: [SearchPresentationScope],
        examples: [String]
    ) {
        self.provider = provider
        self.fields = fields
        self.scopes = scopes
        self.examples = examples
    }
}

public struct SearchCapabilities: Codable, Hashable, Sendable {
    public let contractVersion: Int
    public let providers: [SearchProviderCapability]

    public init(contractVersion: Int, providers: [SearchProviderCapability]) {
        self.contractVersion = contractVersion
        self.providers = providers
    }

    public func capability(for provider: SearchProvider) -> SearchProviderCapability? {
        providers.first { $0.provider == provider }
    }

    public static let current = SearchCapabilities(
        contractVersion: SearchContract.currentVersion,
        providers: [
            SearchProviderCapability(
                provider: .note,
                fields: noteFields,
                scopes: SearchPresentationScope.visibleModes,
                examples: [
                    #"title:"reflective equilibrium" autonomy"#,
                    #"property:language="Greek""#,
                    #"from-note:"Groundwork" relation:supports duty"#,
                ]
            ),
            SearchProviderCapability(
                provider: .record,
                fields: recordFields,
                scopes: SearchPresentationScope.visibleModes,
                examples: [
                    #"kind:record action:"Analyze Note""#,
                    "kind:record participant:researcher date:30d",
                ]
            ),
        ]
    )

    private static let noteFields: [SearchFieldCapability] = [
        SearchFieldCapability(
            name: "kind",
            valueKind: .canonical,
            allowedValues: SearchProvider.allCases.map(\.rawValue),
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: false
        ),
    ] + SearchLexicalField.allCases.map {
        SearchFieldCapability(
            name: $0.rawValue,
            valueKind: .lexical,
            allowsPhrase: true,
            allowsPrefix: true,
            allowsExclusion: true
        )
    } + [
        SearchFieldCapability(
            name: "callout",
            valueKind: .canonical,
            allowedValues: CalloutSemanticRole.allCases.map(\.rawValue),
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: true
        ),
        SearchFieldCapability(
            name: "has",
            valueKind: .canonical,
            allowedValues: ["broken-link"],
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: true
        ),
        SearchFieldCapability(
            name: "property",
            valueKind: .property,
            allowsPhrase: true,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: SearchRelationDirection.fromNote.rawValue,
            valueKind: .noteIdentity,
            allowsPhrase: true,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: SearchRelationDirection.toNote.rawValue,
            valueKind: .noteIdentity,
            allowsPhrase: true,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: "relation",
            valueKind: .canonical,
            allowedValues: SearchRelation.allCases.map(\.rawValue),
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: false
        ),
    ]

    private static let recordFields: [SearchFieldCapability] = [
        SearchFieldCapability(
            name: "kind",
            valueKind: .canonical,
            allowedValues: SearchProvider.allCases.map(\.rawValue),
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: "note",
            valueKind: .noteIdentity,
            allowsPhrase: true,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: "action",
            valueKind: .lexical,
            allowsPhrase: true,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: "skill",
            valueKind: .lexical,
            allowsPhrase: true,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: "participant",
            valueKind: .canonical,
            allowedValues: ["researcher", "agent"],
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: false
        ),
        SearchFieldCapability(
            name: "date",
            valueKind: .canonical,
            allowedValues: ["today", "7d", "30d"],
            allowsPhrase: false,
            allowsPrefix: false,
            allowsExclusion: false
        ),
    ]
}
