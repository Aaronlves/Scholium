import Foundation

/// An instruction shortcut. Source capture and execution are owned by the window and Chat.
struct AgentChatSelectionInquiry: Equatable, Sendable {
    enum ResultKind: Sendable { case discussion, replacement }
    let title: String
    let question: String?
    var resultKind: ResultKind = .discussion

    static var ask: Self { .init(title: ScholiumL10n.string("Ask Agent"), question: nil) }
    static var explain: Self {
        .init(
            title: ScholiumL10n.string("Explain"),
            question:
                ScholiumL10n.string(
                    "Explain the attached passage concisely. Distinguish its explicit claims from your interpretation, and identify uncertainty where context is missing. Do not change Notes."
                ))
    }
    static var polish: Self {
        .init(
            title: ScholiumL10n.string("Polish"),
            question:
                ScholiumL10n.string(
                    "Polish the attached passage while preserving its thesis, terminology, qualifications, citations and Markdown structure. Return only the proposed replacement Markdown, without a code fence or introductory explanation. Do not change Notes."
                ), resultKind: .replacement)
    }
    static var clarifyConcepts: Self {
        .init(
            title: ScholiumL10n.string("Clarify Concepts"),
            question:
                ScholiumL10n.string(
                    "Clarify the key concepts and distinctions in the attached passage, including ambiguities that affect its meaning. Separate the passage’s explicit wording from your interpretation. Discuss in Chat without changing Notes."
                ))
    }
    static var examineArgument: Self {
        .init(
            title: ScholiumL10n.string("Examine Argument"),
            question:
                ScholiumL10n.string(
                    "Examine the claim and reasons in the attached passage, any premises needed for the inference, and the most consequential objection. Distinguish stated premises from your reconstruction; do not force a nonargumentative passage into a proof. Discuss in Chat without changing Notes."
                ))
    }
    static var checkEvidence: Self {
        .init(
            title: ScholiumL10n.string("Check Evidence"),
            question:
                ScholiumL10n.string(
                    "Check the grounds for the attached passage. Distinguish inspected primary sources, analysis Notes and your inferences. Cite only material you have read with its location; leave claims unverified where the required source is unavailable. Discuss in Chat without changing Notes."
                ))
    }
    static var allCases: [Self] { [.ask, .clarifyConcepts, .examineArgument, .checkEvidence] }
}
