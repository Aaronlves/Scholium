import Foundation

public enum SearchTruth: String, Codable, Hashable, Sendable {
    case yes, no, unknown

    public var negated: Self {
        switch self {
        case .yes: .no
        case .no: .yes
        case .unknown: .unknown
        }
    }
}

public struct SearchPredicate: Codable, Hashable, Sendable {
    public let clause: SearchClause
    public let excluded: Bool

    public init(clause: SearchClause, excluded: Bool = false) {
        self.clause = clause
        self.excluded = excluded
    }

    public var explanation: SearchExplanationClause {
        let kind: SearchExplanationClauseKind
        switch clause {
        case .lexical(let value): kind = .lexical(value.field, value.value.text, value.value.matchKind, excluded)
        case .structured(let value): kind = .structured(value.field, value.value, excluded)
        case .property(let value): kind = .property(value.key, value.value)
        case .link(let value): kind = .link(value.direction, value.noteIdentity)
        case .paragraph(let value): kind = .paragraph(value.expression)
        }
        return SearchExplanationClause(kind: kind, sourceRange: clause.sourceRange)
    }
}

public struct SearchEvaluation: Sendable {
    public let truth: SearchTruth
    public let matches: [SearchPredicate]
}

public indirect enum SearchExpression: Codable, Hashable, Sendable {
    case clause(SearchClause)
    case and([SearchExpression])
    case or([SearchExpression])
    case not(SearchExpression)

    public var predicates: [SearchPredicate] { predicates(negated: false) }

    private func predicates(negated: Bool) -> [SearchPredicate] {
        switch self {
        case .clause(let clause): [SearchPredicate(clause: clause, excluded: negated)]
        case .and(let children), .or(let children): children.flatMap { $0.predicates(negated: negated) }
        case .not(let child): child.predicates(negated: !negated)
        }
    }

    public var containsDisjunction: Bool { containsDisjunction(negated: false) }
    private func containsDisjunction(negated: Bool) -> Bool {
        switch self {
        case .clause: false
        case .or(let children): !negated || children.contains { $0.containsDisjunction(negated: true) }
        case .and(let children): negated || children.contains { $0.containsDisjunction(negated: false) }
        case .not(let child): child.containsDisjunction(negated: !negated)
        }
    }

    /// Structural guarantee after pushing negation to leaves, without exponential expansion.
    public var guaranteesPositiveLexicalMatch: Bool { guaranteesPositiveLexicalMatch(negated: false) }

    private func guaranteesPositiveLexicalMatch(negated: Bool) -> Bool {
        switch self {
        case .clause(let clause):
            if case .lexical = clause { return !negated }
            if case .paragraph(let value) = clause { return !negated && value.expression.guaranteesPositiveLexicalMatch }
            return false
        case .not(let child): return child.guaranteesPositiveLexicalMatch(negated: !negated)
        case .and(let children):
            return negated
                ? !children.isEmpty && children.allSatisfy { $0.guaranteesPositiveLexicalMatch(negated: true) }
                : children.contains { $0.guaranteesPositiveLexicalMatch(negated: false) }
        case .or(let children):
            return negated
                ? children.contains { $0.guaranteesPositiveLexicalMatch(negated: true) }
                : !children.isEmpty && children.allSatisfy { $0.guaranteesPositiveLexicalMatch(negated: false) }
        }
    }

    public func evaluate(_ predicate: (SearchClause) -> SearchTruth) -> SearchEvaluation {
        evaluate(negated: false, predicate)
    }

    private func evaluate(negated: Bool, _ predicate: (SearchClause) -> SearchTruth) -> SearchEvaluation {
        switch self {
        case .clause(let clause):
            let value = predicate(clause)
            let truth = negated ? value.negated : value
            return SearchEvaluation(truth: truth, matches: truth == .yes ? [SearchPredicate(clause: clause, excluded: negated)] : [])
        case .not(let child): return child.evaluate(negated: !negated, predicate)
        case .and(let children), .or(let children):
            let conjunctive: Bool
            if case .and = self { conjunctive = !negated } else { conjunctive = negated }
            let evaluations = children.map { $0.evaluate(negated: negated, predicate) }
            let truth: SearchTruth
            if conjunctive {
                truth = evaluations.contains { $0.truth == .no } ? .no : evaluations.contains { $0.truth == .unknown } ? .unknown : .yes
            } else {
                truth = evaluations.contains { $0.truth == .yes } ? .yes : evaluations.contains { $0.truth == .unknown } ? .unknown : .no
            }
            return SearchEvaluation(truth: truth, matches: truth == .yes ? evaluations.filter { $0.truth == .yes }.flatMap(\.matches) : [])
        }
    }

    public func rendered(_ renderClause: (SearchClause) -> String) -> String {
        switch self {
        case .clause(let clause): renderClause(clause)
        case .not(let child): "NOT (" + child.rendered(renderClause) + ")"
        case .and(let children): "(" + children.map { $0.rendered(renderClause) }.joined(separator: " AND ") + ")"
        case .or(let children): "(" + children.map { $0.rendered(renderClause) }.joined(separator: " OR ") + ")"
        }
    }
}

public extension SearchClause {
    var queryDescription: String {
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        switch self {
        case .lexical(let value):
            return (value.field.map { $0.rawValue + ":" } ?? "") + (value.value.isPrefix ? value.value.text + "*" : quote(value.value.text))
        case .structured(let value): return value.field.rawValue + ":" + value.value
        case .property(let value): return "property:" + quote(value.key) + (value.value.map { "=" + quote($0) } ?? "")
        case .link(let value): return value.direction.rawValue + ":" + quote(value.noteIdentity)
        case .paragraph(let value): return "paragraph:" + value.expression.rendered(\.queryDescription)
        }
    }

    var sourceRange: Range<Int> {
        switch self {
        case .lexical(let value): value.sourceRange
        case .structured(let value): value.sourceRange
        case .property(let value): value.sourceRange
        case .link(let value): value.sourceRange
        case .paragraph(let value): value.sourceRange
        }
    }
}

/// One independently authorized graph predicate, including uncertainty needed for exclusion.
public struct SearchLinkResolution: Sendable {
    public let matches: [VaultQualifiedNoteID: SearchLinkMatch]
    public let indeterminateNotes: Set<VaultQualifiedNoteID>

    public init(matches: [VaultQualifiedNoteID: SearchLinkMatch], indeterminateNotes: Set<VaultQualifiedNoteID> = []) {
        self.matches = matches
        self.indeterminateNotes = indeterminateNotes
    }
}
