import Foundation

/// An ephemeral composer shortcut, not a research workflow or persisted method.
enum AgentChatSelectionInquiry: Int, CaseIterable {
  case ask = 0, clarifyConcepts, examineArgument, checkEvidence

  var title: String {
    switch self {
    case .ask: ScholiumL10n.string("Ask Agent")
    case .clarifyConcepts: ScholiumL10n.string("Clarify Concepts")
    case .examineArgument: ScholiumL10n.string("Examine Argument")
    case .checkEvidence: ScholiumL10n.string("Check Evidence")
    }
  }

  var question: String? {
    switch self {
    case .ask: nil
    case .clarifyConcepts:
      ScholiumL10n.string("Clarify the key concepts and distinctions in the attached passage, including ambiguities that affect its meaning. Separate the passage’s explicit wording from your interpretation. Discuss in Chat without changing Notes.")
    case .examineArgument:
      ScholiumL10n.string("Examine the claim and reasons in the attached passage, any premises needed for the inference, and the most consequential objection. Distinguish stated premises from your reconstruction; do not force a nonargumentative passage into a proof. Discuss in Chat without changing Notes.")
    case .checkEvidence:
      ScholiumL10n.string("Check the grounds for the attached passage. Distinguish inspected primary sources, analysis Notes and your inferences. Cite only material you have read with its location; leave claims unverified where the required source is unavailable. Discuss in Chat without changing Notes.")
    }
  }
}
