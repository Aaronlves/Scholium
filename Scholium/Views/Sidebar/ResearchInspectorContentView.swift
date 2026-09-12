import ScholiumContracts
import SwiftUI

// MARK: - Research Inspector content

enum ResearchProjectionFreshness: Equatable, Sendable {
    case refreshing
    case current
    case stale(String)
    case failed(String)
    case unavailable(String)

    var titleResource: LocalizedStringResource {
        switch self {
        case .refreshing: "Refreshing derived state…"
        case .current: "Current for saved source"
        case .stale: "Refresh Needed"
        case .failed: "Refresh Failed"
        case .unavailable: "Refresh Unavailable"
        }
    }

    var detail: String? {
        switch self {
        case .stale(let reason), .failed(let reason), .unavailable(let reason): reason
        case .refreshing, .current: nil
        }
    }

    var permitsRetry: Bool {
        switch self {
        case .stale, .failed: true
        case .refreshing, .current, .unavailable: false
        }
    }

    var isActionable: Bool {
        switch self {
        case .refreshing, .stale, .failed, .unavailable: true
        case .current: false
        }
    }
}

struct ResearchProjectionFreshnessView: View {
    let freshness: ResearchProjectionFreshness
    let retry: () -> Void

    var body: some View {
        Group {
            if freshness.isActionable {
                ScholiumApparatusStateView(
                    freshness.titleResource,
                    detail: freshness.detail,
                    systemImage: systemImage,
                    showsProgress: freshness == .refreshing,
                    density: freshness.detail == nil ? .line : .block
                ) {
                    if freshness.permitsRetry {
                        Button("Retry", action: retry)
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                    }
                }
                .accessibilityIdentifier("scholium.researchProjectionFreshness")
            }
        }
    }

    private var systemImage: String {
        switch freshness {
        case .refreshing: "arrow.triangle.2.circlepath"
        case .current: "checkmark.circle"
        case .stale: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle"
        case .unavailable: "slash.circle"
        }
    }
}

struct ResearchInspectorContentContext {
    let freshness: ResearchProjectionFreshness
    let retryRefresh: () -> Void
}
