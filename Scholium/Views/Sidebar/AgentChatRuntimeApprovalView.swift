import ScholiumContracts
import SwiftUI

struct AgentChatRuntimeApprovalView: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let request: AgentChatRuntimeApproval
  let technicalDetail: String
  let decision: AgentChatRuntimeApproval.Decision?
  let failure: String?
  let respond: (AgentChatRuntimeApproval.Decision) -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            if request.kind != .network, let command = request.command {
              Text(verbatim: command).font(.body.monospaced()).textSelection(.enabled)
            }
            if let reason = request.reason, !reason.isEmpty {
              Text(verbatim: reason).font(.callout).textSelection(.enabled)
            }
            ForEach(Array(request.scopeLines(locale: locale).enumerated()), id: \.offset) { _, line in
              Text(verbatim: line).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(request.files.enumerated()), id: \.offset) { _, file in
              DisclosureGroup {
                Text(verbatim: file.diff).font(.caption.monospaced()).textSelection(.enabled)
              } label: {
                Text(verbatim: file.label(locale: locale)).fixedSize(horizontal: false, vertical: true)
              }
            }
            DisclosureGroup {
              Text(verbatim: technicalDetail).font(.caption.monospaced()).textSelection(.enabled)
            } label: {
              Text("Details", bundle: .module).foregroundStyle(.secondary)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 320)
        if let decision {
          Text(decision.label(locale: locale)).font(.callout)
          if let failure {
            Text(failure).font(.caption).foregroundStyle(.secondary)
          } else {
            HStack(spacing: 8) {
              if reduceMotion {
                Image(systemName: "ellipsis").accessibilityHidden(true)
              } else {
                ProgressView().controlSize(.small).accessibilityHidden(true)
              }
              Text("Waiting for Confirmation…", bundle: .module).font(.caption).foregroundStyle(.secondary)
            }
          }
        } else {
          if request.grants.isEmpty {
            Text("This request has no supported grant here.", bundle: .module).font(.caption).foregroundStyle(
              .secondary)
          }
          HStack {
            Button(request.rejection.label(locale: locale)) { respond(request.rejection) }
            Spacer(minLength: 0)
            if let first = request.grants.first { Button(first.label(locale: locale)) { respond(first) } }
            if request.grants.count > 1 {
              Menu {
                ForEach(Array(request.grants.dropFirst().enumerated()), id: \.offset) { _, grant in
                  Button(grant.label(locale: locale)) { respond(grant) }
                }
              } label: {
                Image(systemName: "ellipsis")
              }
              .help("More Approval Options").accessibilityLabel(Text("More Approval Options", bundle: .module))
            }
          }
        }
      }.padding(6)
    } label: {
      Text(request.title(locale: locale)).font(.headline)
    }
    .padding().accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.runtimeApproval")
  }
}
