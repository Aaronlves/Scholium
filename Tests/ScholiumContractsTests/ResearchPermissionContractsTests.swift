import Foundation
import ScholiumContracts
import Testing

@Suite("Research Permission contracts")
struct ResearchPermissionContractsTests {
    @Test("All three policies remain stable versioned values")
    func policyValuesRoundTrip() throws {
        #expect(ResearchPermissionPolicy.allCases == [
            .askEveryTime,
            .askOnlyForWorks,
            .triptychWide,
        ])
        for policy in ResearchPermissionPolicy.allCases {
            let encoded = try JSONEncoder().encode(policy)
            #expect(try JSONDecoder().decode(
                ResearchPermissionPolicy.self,
                from: encoded
            ) == policy)
        }
    }

    @Test("A Skill envelope digest covers package and every Profile role")
    func envelopeDigestIsCompleteAndDeterministic() throws {
        let firstProfile = try profile(
            actionID: .discuss,
            role: .analysis,
            source: "analysis-profile"
        )
        let secondProfile = try profile(
            actionID: .discuss,
            role: .topic,
            source: "topic-profile"
        )
        let first = try subject(
            packageSource: "method-v1",
            profiles: [secondProfile, firstProfile]
        )
        let reordered = try subject(
            packageSource: "method-v1",
            profiles: [firstProfile, secondProfile]
        )
        let changedSkill = try subject(
            packageSource: "method-v2",
            profiles: [firstProfile, secondProfile]
        )
        let changedProfile = try subject(
            packageSource: "method-v1",
            profiles: [
                firstProfile,
                try profile(
                    actionID: .discuss,
                    role: .topic,
                    source: "topic-profile-v2"
                ),
            ]
        )

        #expect(first.envelopeDigest == reordered.envelopeDigest)
        #expect(first.envelopeDigest != changedSkill.envelopeDigest)
        #expect(first.envelopeDigest != changedProfile.envelopeDigest)
    }

    @Test("Initial Action selection never asks a redundant standing-policy question")
    func initialActionIsAlreadyAuthorized() throws {
        let subject = try subject()
        for policy in ResearchPermissionPolicy.allCases {
            let document = try ResearchPermissionPolicyDocument(
                triptychDefault: policy
            )
            let evaluation = ResearchPermissionPolicyResolver.evaluate(
                document: document,
                request: try request(
                    kind: .initialAction,
                    subject: subject,
                    roles: []
                )
            )
            #expect(evaluation.disposition == .initialTargetAuthorized)
            #expect(evaluation.source == .explicitAction)
        }
    }

    @Test("Triptych policy applies only when no deliberate Skill override exists")
    func inheritanceAndOverride() throws {
        let subject = try subject()
        let inherited = try ResearchPermissionPolicyDocument(
            triptychDefault: .triptychWide
        )
        #expect(try evaluate(inherited, subject: subject, roles: [.work])
            .disposition == .mayIssueBoundedGrant)
        #expect(try evaluate(inherited, subject: subject, roles: [.work])
            .source == .triptychDefault)

        let override = try ResearchSkillPermissionOverride(
            packageID: subject.packageID,
            policy: .askEveryTime,
            approvedEnvelopeDigest: subject.envelopeDigest
        )
        let overridden = try ResearchPermissionPolicyDocument(
            triptychDefault: .triptychWide,
            skillOverrides: [override]
        )
        let result = try evaluate(overridden, subject: subject, roles: [.topic])
        #expect(result.disposition == .requiresResearcherDecision)
        #expect(result.source == .skillOverride)
    }

    @Test("A stale Skill override fails closed instead of inheriting a broader default")
    func changedDigestInvalidatesOverride() throws {
        let approved = try subject(packageSource: "approved")
        let changed = try subject(packageSource: "changed")
        let document = try ResearchPermissionPolicyDocument(
            triptychDefault: .triptychWide,
            skillOverrides: [try ResearchSkillPermissionOverride(
                packageID: approved.packageID,
                policy: .triptychWide,
                approvedEnvelopeDigest: approved.envelopeDigest
            )]
        )

        let result = try evaluate(document, subject: changed, roles: [.analysis])
        #expect(result.effectivePolicy == .askEveryTime)
        #expect(result.source == .invalidatedOverride)
        #expect(result.disposition == .requiresResearcherDecision)
    }

    @Test("Ask Only for Works escalates every Work write and no Analysis or Topic write")
    func worksEscalation() throws {
        let subject = try subject()
        let document = try ResearchPermissionPolicyDocument(
            triptychDefault: .askOnlyForWorks
        )

        #expect(try evaluate(document, subject: subject, roles: [.analysis])
            .disposition == .mayIssueBoundedGrant)
        #expect(try evaluate(document, subject: subject, roles: [.topic])
            .disposition == .mayIssueBoundedGrant)
        #expect(try evaluate(document, subject: subject, roles: [.analysis, .work])
            .disposition == .requiresResearcherDecision)
        #expect(try evaluate(document, subject: subject, roles: [.work])
            .disposition == .requiresResearcherDecision)
    }

    @Test("Unknown versions, fields, duplicate overrides, and malformed requests fail closed")
    func strictValidation() throws {
        let subject = try subject()
        let override = try ResearchSkillPermissionOverride(
            packageID: subject.packageID,
            policy: .askEveryTime,
            approvedEnvelopeDigest: subject.envelopeDigest
        )
        #expect(throws: ResearchPermissionContractError.self) {
            _ = try ResearchPermissionPolicyDocument(
                skillOverrides: [override, override]
            )
        }
        #expect(throws: ResearchPermissionContractError.self) {
            _ = try ResearchStandingPermissionRequest(
                kind: .additionalNoteChanges,
                packageID: subject.packageID,
                currentEnvelopeDigest: subject.envelopeDigest,
                requestedWritableRoles: []
            )
        }

        let valid = try JSONEncoder().encode(
            ResearchPermissionPolicyDocument(triptychDefault: .askEveryTime)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        object["schema_version"] = 99
        #expect(throws: ResearchPermissionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchPermissionPolicyDocument.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object["schema_version"] = 1
        object["unexpected"] = true
        #expect(throws: ResearchPermissionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchPermissionPolicyDocument.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    private func evaluate(
        _ document: ResearchPermissionPolicyDocument,
        subject: ResearchPermissionSubject,
        roles: Set<ResearchActionTargetRole>
    ) throws -> ResearchPermissionEvaluation {
        ResearchPermissionPolicyResolver.evaluate(
            document: document,
            request: try request(
                kind: .additionalNoteChanges,
                subject: subject,
                roles: roles
            )
        )
    }

    private func request(
        kind: ResearchPermissionRequestKind,
        subject: ResearchPermissionSubject,
        roles: Set<ResearchActionTargetRole>
    ) throws -> ResearchStandingPermissionRequest {
        try ResearchStandingPermissionRequest(
            kind: kind,
            packageID: subject.packageID,
            currentEnvelopeDigest: subject.envelopeDigest,
            requestedWritableRoles: roles
        )
    }

    private func subject(
        packageSource: String = "method",
        profiles: [ResearchPermissionProfileRevision]? = nil
    ) throws -> ResearchPermissionSubject {
        try ResearchPermissionSubject(
            packageID: "bounded-method",
            displayName: "Bounded Method",
            packageRevision: DocumentFingerprint(content: packageSource),
            profiles: profiles ?? [try profile(
                actionID: .write,
                role: .work,
                source: "profile"
            )]
        )
    }

    private func profile(
        actionID: ResearchActionID,
        role: ResearchActionTargetRole,
        source: String
    ) throws -> ResearchPermissionProfileRevision {
        try ResearchPermissionProfileRevision(
            actionID: actionID,
            targetRole: role,
            profileRevision: DocumentFingerprint(content: source)
        )
    }
}
