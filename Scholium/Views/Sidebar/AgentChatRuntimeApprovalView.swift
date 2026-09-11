import ScholiumContracts
import SwiftUI

struct AgentChatRuntimeApprovalView: View {
    @Environment(\.locale) private var locale
    let request: AgentChatRuntimeApproval
    let decision: AgentChatRuntimeApproval.Decision?
    let failure: String?
    let stop: () -> Void
    let respond: (AgentChatRuntimeApproval.Decision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentChatContentScroll {
                VStack(alignment: .leading, spacing: 12) {
                    Text(request.question(locale: locale)).font(.headline)
                    if let reason = request.explanation(locale: locale), !reason.isEmpty {
                        Text(verbatim: reason).font(.body).textSelection(.enabled)
                    }
                    if request.kind == .command || request.kind == .terminalInput, let command = request.command {
                        Text(verbatim: command).font(.callout.monospaced()).textSelection(.enabled)
                    }
                    ForEach(Array(request.accessOverview(locale: locale).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line).font(.body).fixedSize(horizontal: false, vertical: true)
                    }

                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let decision {
                Text(decision.label(locale: locale)).font(.callout).foregroundStyle(.secondary)
                AgentChatSubmissionStatus(failure: failure)
                if failure != nil { Button("End Turn", action: stop) }
            } else {
                if request.grants.isEmpty {
                    Text("This request has no supported grant here.", bundle: .module).font(.caption).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        rejection
                        Spacer(minLength: 8)
                        grants
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            rejection
                            Spacer(minLength: 0)
                        }
                        grants
                    }
                }.controlSize(.regular)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.runtimeApproval")
    }

    private var rejection: some View {
        Button(request.rejection.label(locale: locale)) { respond(request.rejection) }.fixedSize()
    }

    @ViewBuilder
    private var grants: some View {
        HStack(spacing: 8) {
            if request.grants.count > 1 {
                Menu {
                    ForEach(Array(request.grants.dropFirst().enumerated()), id: \.offset) { _, grant in
                        Button(grant.label(locale: locale)) { respond(grant) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                .help("More Approval Options").accessibilityLabel(Text("More Approval Options", bundle: .module))
            }
            if let first = request.grants.first {
                Button(first.label(locale: locale)) { respond(first) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).fixedSize()
            }
        }
    }
}
