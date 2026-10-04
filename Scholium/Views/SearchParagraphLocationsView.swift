import ScholiumContracts
import SwiftUI

struct SearchParagraphLocationsView: View {
    let note: NoteSearchResult
    let open: (SearchResultSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var visibleCount = 10
    var body: some View {
        VStack(alignment: .leading) {
            Text(note.title).font(.headline)
            Text("\(note.paragraphRanges.count) Matching Paragraphs").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(Array(note.paragraphRanges.prefix(visibleCount).enumerated()), id: \.offset) { _, range in
                        Button {
                            if let target = note.selectingParagraph(range) { open(.result(.note(target))) }
                        } label: {
                            Text("Paragraph at line \(range.line)")
                        }
                        .buttonStyle(ScholiumContentActionButtonStyle())
                        .accessibilityLabel(Text("Paragraph at line \(range.line)"))
                    }
                    if visibleCount < note.paragraphRanges.count {
                        Button("Show More Paragraphs") { visibleCount += 10 }
                            .buttonStyle(ScholiumContentActionButtonStyle())
                            .accessibilityLabel("Show More Paragraphs")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 320)
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(minWidth: 260)
        .accessibilityIdentifier("scholium.searchParagraphLocations")
    }
}
