import Foundation

/// Owns one Read surface's one-shot scroll requests, claim tokens, consumed
/// history, and latest observed semantic position. WebKit measurement and page
/// identity remain with the parent coordinator.
struct SafeMarkdownReadScrollRestoration {
    struct Claim {
        let token: UInt64
        let request: ScrollRestoreRequest
        let ownership: Ownership
    }

    enum Ownership {
        case caller
        case coordinator
    }

    private struct Identity: Equatable {
        let id: UInt64
        let fingerprint: String
    }

    private static let consumedHistoryLimit = 64
    private var request: ScrollRestoreRequest?
    private var ownership: Ownership?
    private var consumed: [Identity] = []
    private var inFlightClaim: Claim?
    private var nextClaimToken: UInt64 = 0
    private var nextInternalRequestID = UInt64.max
    private var onCallerRequestConsumed: ((UInt64, String) -> Void)?
    var observedPosition: ObservedScrollPosition

    init(
        observedPosition: ObservedScrollPosition,
        request: ScrollRestoreRequest?,
        onCallerRequestConsumed: ((UInt64, String) -> Void)?
    ) {
        self.observedPosition = observedPosition
        self.request = request
        ownership = request == nil ? nil : .caller
        self.onCallerRequestConsumed = onCallerRequestConsumed
    }

    mutating func update(
        observedPosition: ObservedScrollPosition,
        onCallerRequestConsumed: ((UInt64, String) -> Void)?
    ) {
        self.observedPosition = observedPosition
        self.onCallerRequestConsumed = onCallerRequestConsumed
    }

    mutating func adoptCallerRequest(_ next: ScrollRestoreRequest?) {
        guard let next else {
            guard ownership == .caller else { return }
            if inFlightClaim?.ownership == .caller { inFlightClaim = nil }
            request = nil
            ownership = nil
            return
        }
        guard !hasConsumed(next) else {
            if ownership == .caller, request.map({ sameIdentity($0, next) }) == true {
                request = nil
                ownership = nil
            }
            return
        }
        request = next
        ownership = .caller
    }

    mutating func ensureRequest(
        fingerprint: String,
        reason: ScrollRestoreReason
    ) {
        if let request,
           request.fingerprint == fingerprint,
           !hasConsumed(request) {
            return
        }
        let matchingAnchor = observedPosition.anchor.flatMap { anchor in
            anchor.sourceFingerprint == fingerprint ? anchor : nil
        }
        request = ScrollRestoreRequest(
            id: nextInternalRequestID,
            fingerprint: fingerprint,
            position: ObservedScrollPosition(
                fraction: observedPosition.fraction,
                anchor: matchingAnchor
            ),
            reason: reason
        )
        ownership = .coordinator
        nextInternalRequestID &-= 1
    }

    mutating func claimIfReady(
        pageIsReady: Bool,
        fingerprint: String
    ) -> Claim? {
        guard pageIsReady,
              let request,
              let ownership,
              request.fingerprint == fingerprint,
              !hasConsumed(request),
              !sameIdentity(inFlightClaim?.request, request) else { return nil }
        nextClaimToken &+= 1
        let claim = Claim(
            token: nextClaimToken,
            request: request,
            ownership: ownership
        )
        inFlightClaim = claim
        return claim
    }

    mutating func finish(_ claim: Claim, consumed: Bool) {
        guard inFlightClaim?.token == claim.token else { return }
        inFlightClaim = nil
        guard consumed else { return }
        recordConsumed(claim.request)
        if request.map({ sameIdentity($0, claim.request) }) == true {
            request = nil
            ownership = nil
        }
        if claim.ownership == .caller {
            onCallerRequestConsumed?(claim.request.id, claim.request.fingerprint)
        }
    }

    func owns(_ claim: Claim) -> Bool {
        inFlightClaim?.token == claim.token
    }

    func hasPendingRequest(fingerprint: String) -> Bool {
        request.map { request in
            request.fingerprint == fingerprint
                && !hasConsumed(request)
                && !sameIdentity(inFlightClaim?.request, request)
        } == true
    }

    mutating func cancelClaim() {
        inFlightClaim = nil
    }

    private func sameIdentity(
        _ lhs: ScrollRestoreRequest?,
        _ rhs: ScrollRestoreRequest
    ) -> Bool {
        lhs?.id == rhs.id && lhs?.fingerprint == rhs.fingerprint
    }

    private func hasConsumed(_ request: ScrollRestoreRequest) -> Bool {
        consumed.contains(Identity(id: request.id, fingerprint: request.fingerprint))
    }

    private mutating func recordConsumed(_ request: ScrollRestoreRequest) {
        let identity = Identity(id: request.id, fingerprint: request.fingerprint)
        guard !consumed.contains(identity) else { return }
        consumed.append(identity)
        let overflow = consumed.count - Self.consumedHistoryLimit
        if overflow > 0 { consumed.removeFirst(overflow) }
    }
}
