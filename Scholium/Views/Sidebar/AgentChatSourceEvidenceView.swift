import ScholiumContracts
import SwiftUI

struct AgentChatSourceEvidenceView: View {
  let evidence: AgentChatSourceEvidence
  @Binding var isExpanded: Bool
  var body: some View {
    Group {
      switch evidence {
      case .unrecorded:
        Text("No reading range recorded for this turn")
      case .differentRevision:
        Text("Read a different version")
      case .web(let access):
        DisclosureGroup("Web Access Reported", isExpanded: $isExpanded) {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(access.enumerated()), id: \.offset) { _, item in
              Text(item.action == .openPage ? "Open Page" : "Find in Page")
            }
            Text("The runtime reported access, without full-text reading coverage.")
          }.padding(.top, 4)
        }
      case .note(let coverage):
        DisclosureGroup(isExpanded: $isExpanded) {
          VStack(alignment: .leading, spacing: 8) {
            if let read = coverage.reads.last {
              Text("Source version: \(String(read.fingerprint.sha256.prefix(12)))")
                .help(read.fingerprint.sha256).textSelection(.enabled)
            }
            if !coverage.coversCitedLine { Text("The cited line is outside the recorded reading ranges.") }
            ForEach(Array(coverage.reads.enumerated()), id: \.offset) { _, read in
              VStack(alignment: .leading, spacing: 4) {
                Text("Read from line \(read.startLine), \(read.lineCount) lines")
                if !read.excerpt.isEmpty {
                  Text(read.excerpt)
                    .font(.callout)
                    .foregroundStyle(ScholiumNativeColorRole.label.color)
                    .textSelection(.enabled)
                }
                if read.excerptIsTruncated { Text("Preview excerpt") }
              }
            }
          }.padding(.top, 4)
        } label: {
          if !coverage.coversCitedLine { Text("Cited location not read") }
          else if coverage.coversWholeSource { Text("Full source received") }
          else if coverage.ranges.isEmpty { Text("No source text returned") }
          else { Text("Read lines \(coverage.lineDescription)") }
        }
      }
    }
    .font(.caption).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
  }
}
