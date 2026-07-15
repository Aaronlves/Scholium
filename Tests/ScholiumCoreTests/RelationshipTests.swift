import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Relationship semantics")
struct RelationshipTests {
    private let locator = SourceLocator(file: "output/chapter.md", line: 12, column: 4)

    @Test("Derived relationship identifiers are deterministic")
    func deterministicRelationshipIdentity() {
        let first = RelationshipEdge.explicit(
            containingPath: "claim.md", targetPath: "question.md", predicate: .answers,
            locator: locator, resolution: .resolved("question.md")
        )
        let second = RelationshipEdge.explicit(
            containingPath: "claim.md", targetPath: "question.md", predicate: .answers,
            locator: locator, resolution: .resolved("question.md")
        )
        #expect(first.id == second.id)
    }

    @Test("Linked paper supports the containing output")
    func supportsDirection() {
        let edge = RelationshipEdge.explicit(
            containingPath: "output/chapter.md",
            targetPath: "papers/paper.md",
            predicate: .supports,
            locator: locator,
            resolution: .resolved("papers/paper.md")
        )
        #expect(edge.subjectPath == "papers/paper.md")
        #expect(edge.objectPath == "output/chapter.md")
    }

    @Test("Citation direction runs from containing note to target")
    func citationDirection() {
        let edge = RelationshipEdge.explicit(
            containingPath: "output/chapter.md",
            targetPath: "papers/paper.md",
            predicate: .cites,
            locator: locator,
            resolution: .resolved("papers/paper.md")
        )
        #expect(edge.subjectPath == "output/chapter.md")
        #expect(edge.objectPath == "papers/paper.md")
    }

    @Test("Untyped and transitive connections never become evidence")
    func noInferredEvidence() {
        let first = RelationshipEdge.explicit(
            containingPath: "output/chapter.md",
            targetPath: "topics/topic.md",
            predicate: .connected,
            locator: locator,
            resolution: .resolved("topics/topic.md")
        )
        let second = RelationshipEdge.explicit(
            containingPath: "topics/topic.md",
            targetPath: "papers/paper.md",
            predicate: .supports,
            locator: SourceLocator(file: "topics/topic.md", line: 8, column: 1),
            resolution: .resolved("papers/paper.md")
        )
        #expect(first.predicate.isSubstantive == false)
        #expect(RelationshipTrace(edges: [first, second]).assertedPredicate == nil)
        #expect(RelationshipTrace(edges: [first]).assertedPredicate == nil)
        #expect(RelationshipTrace(edges: [first]).classification == .directConnection)
    }

    @Test("Workflow relations preserve category, evidence status, and direction")
    func workflowPredicates() {
        let objection = RelationshipEdge.explicit(
            containingPath: "objections/OBJ-001.md",
            targetPath: "arguments/ARG-001.md",
            predicate: .objectsTo,
            locator: locator,
            resolution: .resolved("arguments/ARG-001.md")
        )
        #expect(objection.subjectPath == "objections/OBJ-001.md")
        #expect(objection.objectPath == "arguments/ARG-001.md")
        #expect(objection.predicate.category == .argument)
        #expect(objection.predicate.conveysPositiveEvidence == false)

        let source = RelationshipEdge.explicit(
            containingPath: "imports/IMP-001.md",
            targetPath: "claims/CLM-001.md",
            predicate: .isSourceFor,
            locator: locator,
            resolution: .resolved("claims/CLM-001.md")
        )
        #expect(source.subjectPath == "imports/IMP-001.md")
        #expect(source.predicate.category == .evidence)
        #expect(source.predicate.conveysPositiveEvidence)

        #expect(RelationshipPredicate.isNotEvidenceFor.conveysPositiveEvidence == false)
        #expect(RelationshipPredicate.isNotEvidenceFor.requiresGovernanceAttention)
        #expect(RelationshipPredicate.dependsOn.category == .governance)
        #expect(RelationshipPredicate.supersedes.category == .revision)
    }
}
