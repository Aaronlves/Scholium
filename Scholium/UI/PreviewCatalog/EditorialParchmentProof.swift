#if DEBUG
import Foundation
import SwiftUI

private let editorialParchmentProofScrollSpace = "scholium.editorialParchmentProof.connect"

/// A development-only complete-window acceptance board for the approved
/// Editorial Parchment direction. It now consumes the production Variables
/// and Components so visual review cannot drift into a second palette.
struct EditorialParchmentProof: View {
    @State private var location: NoteLocationScope = .workspace

    var body: some View {
        HStack(spacing: 0) {
            proofSidebar
                .frame(width: 300)

            proofDivider

            proofDocument
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            proofDivider

            proofInspector
                .frame(width: 320)
        }
        .frame(width: 1_180, height: 760)
        .background(ScholiumColorRole.documentBackground.color)
        .foregroundStyle(ScholiumColorRole.primaryText.color)
        .tint(ScholiumColorRole.accent.color)
        .preferredColorScheme(.light)
        .accessibilityIdentifier("scholium.editorialParchmentProof")
    }

    private var proofDivider: some View {
        ScholiumStructuralRule(orientation: .vertical)
            .frame(width: 1)
    }

    // MARK: - Navigation binding

    private var proofSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Scholium")
                    .font(ScholiumInterfaceTypography.identity)
                    .foregroundStyle(ScholiumColorRole.primaryText.color)

                Menu("Dissertation") {
                    Button("Dissertation", action: {})
                    Button("Book Project", action: {})
                    Divider()
                    Button("Manage Triptychs…", action: {})
                }
                .menuStyle(.borderlessButton)
                .font(ScholiumInterfaceTypography.editorialLabel)
                .tint(ScholiumColorRole.secondaryText.color)
                .fixedSize()
                .padding(.top, 3)

                proofScopeIndex
                    .padding(.top, 20)

                proofAttention
                    .padding(.top, 13)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScholiumStructuralRule()

            proofLocationHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    proofFolder("Conceptual architecture", isExpanded: true)
                    proofFolder("Current chapter", level: 1, isExpanded: true)
                    proofFolder("Objections and replies", level: 2, isExpanded: true)
                    proofNote(
                        "The value-first objection under delayed confirmation — 关于规范理由与可修正判断",
                        level: 3
                    )
                    proofNote("QA Autosave B", level: 2)
                    proofFolder("Methods and source boundaries", isExpanded: true)
                    proofNote("Evidence is not connection", level: 1, isSelected: true)
                    proofFolder("Earlier formulations", isExpanded: false)
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)

            proofRecommendedBibliography
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(ScholiumColorRole.navigationSurfaceBackground.color)
    }

    private var proofScopeIndex: some View {
        HStack(spacing: 0) {
            proofScope("Analyses", isSelected: true)
            proofScope("Topics", isSelected: false)
            proofScope("Works", isSelected: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scope")
    }

    private func proofScope(_ title: String, isSelected: Bool) -> some View {
        Button(action: {}) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? ScholiumColorRole.primaryText.color
                        : ScholiumColorRole.secondaryText.color
                )
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            ScholiumEditorialIndexUnderline(
                isSelected: isSelected,
                width: ScholiumMetrics.Library.scopeIndicatorWidth,
                height: ScholiumMetrics.Library.scopeIndicatorHeight
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var proofAttention: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(ScholiumColorRole.accent.color)
                    .accessibilityHidden(true)
                Text(verbatim: "ATTENTION")
                    .font(ScholiumInterfaceTypography.editorialLabel)
                    .tracking(0.8)
                Spacer()
                Text(verbatim: "7")
                    .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attention, 7 items")
    }

    private var proofLocationHeader: some View {
        HStack(spacing: 8) {
            ScholiumLibraryLocationPicker(selection: $location)

            Spacer(minLength: 0)

            proofIconButton("Filter Library", systemImage: "line.3.horizontal.decrease")
            proofIconButton("Create Note", systemImage: "plus")
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    private func proofIconButton(_ label: String, systemImage: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ScholiumColorRole.secondaryText.color)
        .help(label)
        .accessibilityLabel(label)
    }

    private func proofFolder(
        _ title: String,
        level: Int = 0,
        isExpanded: Bool
    ) -> some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(level) * 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .help(title)
    }

    private func proofNote(
        _ title: String,
        level: Int,
        isSelected: Bool = false
    ) -> some View {
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .frame(width: 12)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(level) * 16)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? ScholiumColorRole.raisedSurfaceBackground.color : .clear
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(ScholiumColorRole.accent.color)
                        .frame(width: 2)
                }
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var proofRecommendedBibliography: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScholiumStructuralRule()

            Button(action: {}) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(verbatim: "RECOMMENDED BIBLIOGRAPHY")
                            .font(ScholiumInterfaceTypography.editorialLabel)
                            .tracking(0.7)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ScholiumColorRole.mutedText.color)
                    }
                    Text(verbatim: "No recommendations")
                        .font(ScholiumInterfaceTypography.bibliographyEmptyState)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
                .padding(.top, ScholiumMetrics.Library.bibliographyTopInset)
                .padding(.bottom, ScholiumMetrics.Library.bibliographyBottomInset)
            }
            .buttonStyle(ScholiumQuietRowButtonStyle(
                isHovering: false,
                minimumHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                horizontalInset: ScholiumMetrics.Library.contentInset,
                verticalInset: 0
            ))
            .accessibilityLabel("Open Recommended Bibliography")
            .accessibilityValue("No recommendations")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Triptych Recommended Bibliography")
    }

    // MARK: - Illuminated document

    private var proofDocument: some View {
        VStack(spacing: 0) {
            proofDocumentToolbar

            ScholiumStructuralRule()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "QA Autosave A")
                        .font(ScholiumInterfaceTypography.documentTitle)
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .frame(maxWidth: .infinity, alignment: .center)

                    ScholiumStructuralRule()
                        .padding(.top, 18)

                    proofSectionTitle("Fixture boundary")
                        .padding(.top, 46)

                    Text(verbatim: "This is deterministic, disposable, nonprivate test material. It contains no real source claims and makes no philosophical attribution.")
                        .padding(.top, 16)

                    Text(verbatim: "This synthetic note exercises the complete Scholium editing dialect.")
                        .padding(.horizontal, 48)
                        .padding(.top, 34)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(ScholiumColorRole.accent.color)
                            .frame(width: 2)
                        Text(verbatim: "Synthetic source boundary")
                            .italic()
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }
                    .background(ScholiumColorRole.surfaceBackground.color)
                    .padding(.top, 34)

                    proofSectionTitle("Curated fixture connections")
                        .padding(.top, 34)

                    Text(verbatim: "analysis-032, analysis-033, analysis-034, and analysis-035 remain visible as connections without being presented as evidence.")
                        .padding(.top, 14)

                    Text(verbatim: "Fixture statement Metadata, Markdown source, and rendered presentation remain distinct test layers.")
                        .padding(.top, 22)

                    proofSectionTitle("Working distinction")
                        .padding(.top, 30)

                    Text(verbatim: "A stable source context should make navigation legible without turning its surrounding apparatus into a second document.")
                        .padding(.top, 14)
                }
                .font(ScholiumTypography.swiftUIReadingFont(size: 15, relativeTo: .body))
                .lineSpacing(9)
                .padding(.horizontal, 48)
                .padding(.top, 32)
                .padding(.bottom, 120)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
        }
        .background(ScholiumColorRole.documentBackground.color)
    }

    private var proofDocumentToolbar: some View {
        HStack(spacing: 14) {
            proofIconButton("Show Sidebar", systemImage: "sidebar.left")
            Text(verbatim: "QA Autosave A")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Review", action: {})
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
            proofIconButton("Search", systemImage: "magnifyingglass")
            proofIconButton("Show Research Record", systemImage: "clock.arrow.circlepath")
            proofIconButton("Hide Inspector", systemImage: "sidebar.right")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func proofSectionTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(ScholiumTypography.swiftUIReadingFont(size: 22, relativeTo: .title2))
            .fontWeight(.semibold)
            .foregroundStyle(ScholiumColorRole.primaryText.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Marginal apparatus

    private var proofInspector: some View {
        VStack(spacing: 0) {
            proofModeIndex

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 18,
                    pinnedViews: [.sectionHeaders]
                ) {
                    Section {
                        proofConnectionCluster(
                            .supports,
                            titles: (3...16).map(proofAnalysisTitle)
                        )
                        proofConnectionCluster(
                            .opposes,
                            titles: (296...305).map(proofAnalysisTitle)
                        )
                    } header: {
                        proofConnectionHeading("NEIGHBOR ANALYSES", count: "70")
                    }

                    Section {
                        proofConnectionCluster(
                            .incompatible,
                            titles: [
                                "Epistemic patience",
                                "Recoverable commitment",
                                "Revision-sensitive judgment",
                            ]
                        )
                    } header: {
                        proofConnectionHeading("RELATED TOPICS", count: "24")
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 80)
            }
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: editorialParchmentProofScrollSpace)
        }
        .background(ScholiumColorRole.apparatusSurfaceBackground.color)
    }

    private var proofModeIndex: some View {
        HStack(spacing: 0) {
            proofInspectorMode("Overview", isSelected: false)
            proofInspectorMode("Connect", isSelected: true)
            proofInspectorMode("Actions", isSelected: false)
        }
        .padding(.horizontal, 28)
        .frame(height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research Inspector")
    }

    private func proofInspectorMode(_ title: String, isSelected: Bool) -> some View {
        Button(action: {}) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? ScholiumColorRole.primaryText.color
                        : ScholiumColorRole.secondaryText.color
                )
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            ScholiumEditorialIndexUnderline(
                isSelected: isSelected,
                width: ScholiumMetrics.Apparatus.selectedModeIndicatorWidth,
                height: ScholiumMetrics.Apparatus.selectedModeIndicatorHeight
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func proofConnectionHeading(_ title: String, count: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                Spacer(minLength: 0)
                Text(verbatim: count)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The backing exists only to occlude scrolling rows and exactly matches
        // the surrounding apparatus, so it never reads as a rectangular tile.
        .scholiumSurface(.apparatus)
    }

    private func proofConnectionCluster(
        _ kind: EditorialConnectionKind,
        titles: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(titles, id: \.self) { title in
                Button(action: {}) {
                    Text(verbatim: title)
                        .font(ScholiumTypography.swiftUIReadingFont(size: 12, relativeTo: .body))
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title)
            }
        }
        .padding(.leading, 28)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(editorialParchmentProofScrollSpace))
                let desiredOffset = max(0, 36 - frame.minY)
                let maximumOffset = max(0, geometry.size.height - 36)

                EditorialConnectionMark(
                    kind: kind,
                    color: ScholiumColorRole.secondaryText.color
                )
                    .frame(width: 20, height: 20)
                    .frame(width: 24, height: 36, alignment: .top)
                    // The occlusion backing matches the ambient paper exactly;
                    // even while pinned it never becomes a symbol tile.
                    .scholiumSurface(.apparatus)
                    .offset(y: min(desiredOffset, maximumOffset))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func proofAnalysisTitle(_ index: Int) -> String {
        "Analysis \(String(format: "%03d", index)) — Synthetic Scholium Fixture"
    }
}

private enum EditorialConnectionKind {
    case supports
    case opposes
    case incompatible
}

private struct EditorialConnectionMark: View {
    let kind: EditorialConnectionKind
    let color: Color

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 20
            let scaleY = size.height / 20
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scaleX, y: y * scaleY)
            }

            var path = Path()
            switch kind {
            case .supports:
                path.move(to: point(3.1, 10.1))
                path.addCurve(
                    to: point(16.9, 10.2),
                    control1: point(7.1, 9.9),
                    control2: point(11.8, 10.1)
                )
                path.move(to: point(4.4, 14.5))
                path.addCurve(
                    to: point(10.5, 10),
                    control1: point(6.2, 11.9),
                    control2: point(8.1, 10.5)
                )
            case .opposes:
                path.move(to: point(3.1, 10.1))
                path.addCurve(
                    to: point(13.8, 10.2),
                    control1: point(6.9, 9.9),
                    control2: point(10.5, 10.1)
                )
                path.move(to: point(14.2, 5.7))
                path.addCurve(
                    to: point(14.2, 14.3),
                    control1: point(13.7, 8.5),
                    control2: point(13.7, 11.4)
                )
            case .incompatible:
                path.move(to: point(3.1, 10.1))
                path.addCurve(
                    to: point(9.2, 10.2),
                    control1: point(5.6, 9.9),
                    control2: point(7.6, 10)
                )
                path.addLine(to: point(10, 7.1))
                path.move(to: point(16.9, 10.1))
                path.addCurve(
                    to: point(10.8, 10.2),
                    control1: point(14.4, 9.9),
                    control2: point(12.4, 10)
                )
                path.addLine(to: point(10, 13.1))
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

#Preview("Editorial Parchment — Complete Window") {
    EditorialParchmentProof()
}
#endif
