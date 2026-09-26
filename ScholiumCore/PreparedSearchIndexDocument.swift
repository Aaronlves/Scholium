import Foundation
import ScholiumContracts

/// Transaction-local material. Neither the inventory nor the index actor keeps
/// these large text/coordinate projections after the publication task finishes.
struct PreparedSearchIndexDocument: Sendable {
    let source: SearchIndexDocument
    let projection: SearchDocumentProjection
    let properties: SearchPropertyProjection
    let preparation: SearchProjectionPreparation

    init(source: SearchIndexDocument, cache: SourceSearchProjectionCache?) {
        self.source = source
        let cache = cache.flatMap { $0.isBound(to: source.vaultID, role: source.vaultRole) ? $0 : nil }
        let readStart = ContinuousClock.now
        let cached = cache?.load(for: source.document)
        let cacheReadDuration = readStart.duration(to: .now)
        let computeStart = ContinuousClock.now
        let base =
            cached
            ?? SearchDocumentProjection(
                document: source.document,
                profile: WorkflowProfileResolver.resolve(vaultRole: source.vaultRole),
                semantic: source.semantic)
        projection = base.applyingDynamicState(hasBrokenLink: source.hasBrokenLink)
        properties = SearchPropertyProjection(document: source.document)
        let projectionDuration = computeStart.duration(to: .now)
        let writeStart = ContinuousClock.now
        if cached == nil { cache?.store(base, for: source.document) }
        preparation = SearchProjectionPreparation(
            projectedDocuments: cached == nil ? 1 : 0,
            restoredSearchProjections: cached == nil ? 0 : 1,
            projectionDuration: projectionDuration,
            cacheReadDuration: cacheReadDuration,
            cacheWriteDuration: writeStart.duration(to: .now))
    }
}

struct SearchProjectionPreparation: Sendable {
    var projectedDocuments = 0
    var restoredSearchProjections = 0
    var projectionDuration = Duration.zero
    var cacheReadDuration = Duration.zero
    var cacheWriteDuration = Duration.zero

    mutating func add(_ other: Self) {
        projectedDocuments += other.projectedDocuments
        restoredSearchProjections += other.restoredSearchProjections
        projectionDuration += other.projectionDuration
        cacheReadDuration += other.cacheReadDuration
        cacheWriteDuration += other.cacheWriteDuration
    }
}
