import AppKit
import Foundation
import ScholiumContracts
import SwiftUI

struct DocumentOutlineEntry: Hashable, Identifiable, Sendable {
  let id: String
  let level: Int
  let title: String
  let sourceLine: Int
  let sourceUTF16Offset: Int
  let sourceProgress: Double
}

enum DocumentOutlineProjection {
  static func make(relativePath: String, source: String) -> [DocumentOutlineEntry] {
    guard !source.isEmpty else { return [] }

    let document = NoteDocument(
      relativePath: relativePath,
      rawContent: source
    )
    let semantic = MarkdownSemanticDocument(parsing: document)
    let lineCount = max(1, source.components(separatedBy: .newlines).count)
    let lineDenominator = max(1, lineCount - 1)

    return semantic.headings.enumerated().compactMap { index, heading in
      guard heading.level <= 2 else { return nil }
      let line = max(1, heading.span.start.line)
      let progress = min(
        1,
        max(0, Double(line - 1) / Double(lineDenominator))
      )
      return DocumentOutlineEntry(
        id: String(heading.span.utf16LowerBound) + "-" + String(index),
        level: min(2, max(1, heading.level)),
        title: heading.text,
        sourceLine: line,
        sourceUTF16Offset: max(0, heading.span.utf16LowerBound),
        sourceProgress: progress
      )
    }
  }

  static func activeEntryID(
    entries: [DocumentOutlineEntry],
    sourceUTF16Offset: Int?,
    scrollFraction: Double
  ) -> DocumentOutlineEntry.ID? {
    guard let first = entries.first else { return nil }

    if let sourceUTF16Offset {
      let offset = max(0, sourceUTF16Offset)
      return entries.last(where: { $0.sourceUTF16Offset <= offset })?.id
        ?? first.id
    }

    let progress = min(1, max(0, scrollFraction))
    return entries.last(where: { $0.sourceProgress <= progress })?.id
      ?? first.id
  }
}

struct DocumentOutlineRail: View {
  let entries: [DocumentOutlineEntry]
  let activeEntryID: DocumentOutlineEntry.ID?
  let select: (DocumentOutlineEntry) -> Void

  @Environment(\.scholiumIncreasedContrast) private var increasedContrast
  @Environment(\.scholiumReduceMotion) private var reduceMotion
  @FocusState private var focusedEntryID: DocumentOutlineEntry.ID?
  @State private var pointerRow: CGFloat?
  @State private var hapticRow: Int?
  @State private var lastHoverHapticTime: TimeInterval = 0
  @State private var dismissedPreviewID: DocumentOutlineEntry.ID?

  var body: some View {
    GeometryReader { proxy in
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            markerButton(for: entry, at: index)
          }
        }
        .onContinuousHover { phase in
          switch phase {
          case .active(let location):
            updatePointer(at: location.y)
          case .ended:
            pointerRow = nil
            hapticRow = nil
          }
        }
        .padding(.vertical, ScholiumMetrics.Document.outlineRailVerticalInset)
        .frame(minHeight: proxy.size.height)
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
    }
    .frame(width: ScholiumMetrics.Document.outlineRailWidth)
    .onChange(of: entries) { _, _ in
      pointerRow = nil
      hapticRow = nil
      dismissedPreviewID = nil
    }
    .onChange(of: previewCandidateID) { _, candidate in
      if candidate != dismissedPreviewID { dismissedPreviewID = nil }
    }
    .overlayPreferenceValue(DocumentOutlineMarkerBounds.self) { bounds in
      GeometryReader { proxy in
        if let entry = previewEntry, let anchor = bounds[entry.id] {
          let rect = proxy[anchor]
          if rect.intersects(CGRect(origin: .zero, size: proxy.size)) {
            Text(verbatim: entry.title.isEmpty ? ScholiumL10n.string("Heading") : entry.title)
              .font(.caption)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
              .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
              .scholiumFloatingSurface(
                in: RoundedRectangle(
                  cornerRadius: ScholiumMetrics.Document.outlinePreviewCornerRadius,
                  style: .continuous
                )
              )
              .frame(width: ScholiumMetrics.Document.outlinePreviewWidth, alignment: .leading)
              .position(
                x: rect.maxX + ScholiumGrid.Spacing.labelAccessoryGap
                  + ScholiumMetrics.Document.outlinePreviewWidth / 2,
                y: rect.midY
              )
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
      }
    }
    .onExitCommand { dismissPreview() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(ScholiumL10n.string("Outline"))
    .accessibilityIdentifier("scholium.documentOutlineRail")
  }

  private func markerButton(for entry: DocumentOutlineEntry, at index: Int) -> some View {
    let isActive = activeEntryID == entry.id
    let influence = interactionInfluence(at: index)
    let restingWidth =
      entry.level == 1
      ? ScholiumMetrics.Document.outlineMarkerHeadingOneWidth
      : ScholiumMetrics.Document.outlineMarkerHeadingTwoWidth
    let headingLabel =
      entry.title.isEmpty
      ? ScholiumL10n.string("Heading")
      : entry.title
    let levelLabel = String.localizedStringWithFormat(
      ScholiumL10n.string("Heading %lld"),
      entry.level
    )
    let value =
      isActive
      ? levelLabel + ", " + ScholiumL10n.string("Selected")
      : levelLabel

    return Button {
      dismissPreview()
      select(entry)
    } label: {
      Capsule(style: .continuous)
        .fill(markerColor(isActive: isActive, influence: influence))
        .frame(
          width: restingWidth
            + influence
            * (ScholiumMetrics.Document.outlineMarkerHoverMaximumWidth
              - restingWidth),
          height: max(
            isActive ? ScholiumMetrics.Document.outlineMarkerActiveHeight : 0,
            ScholiumMetrics.Document.outlineMarkerHeight
              + influence
              * (ScholiumMetrics.Document.outlineMarkerHoverHeight
                - ScholiumMetrics.Document.outlineMarkerHeight)
          )
        )
        .frame(
          width: ScholiumMetrics.Document.outlineRailWidth,
          height: ScholiumMetrics.Document.outlineMarkerTarget,
          alignment: .leading
        )
        .contentShape(Rectangle())
        .animation(ScholiumMotion.outlineInteraction(reduceMotion: reduceMotion), value: influence)
        .animation(ScholiumMotion.outlineInteraction(reduceMotion: reduceMotion), value: isActive)
    }
    .buttonStyle(DocumentOutlineMarkerButtonStyle(reduceMotion: reduceMotion))
    .scholiumActivationPointer()
    // Activation-only focus follows keyboard navigation, rather than a
    // pointer press. SwiftUI owns the keyboard focus effect.
    .focusable(interactions: .activate)
    .focused($focusedEntryID, equals: entry.id)
    .anchorPreference(key: DocumentOutlineMarkerBounds.self, value: .bounds) {
      [entry.id: $0]
    }
    .accessibilityLabel(Text(verbatim: headingLabel))
    .accessibilityValue(Text(verbatim: value))
    .accessibilityIdentifier("scholium.documentOutline.heading.\(entry.sourceLine)")
    .accessibilityAddTraits(isActive ? .isSelected : [])
  }

  private var previewEntry: DocumentOutlineEntry? {
    guard let candidate = previewCandidateID, candidate != dismissedPreviewID else { return nil }
    return entries.first(where: { $0.id == candidate })
  }

  private var previewCandidateID: DocumentOutlineEntry.ID? {
    if let pointerRow, !entries.isEmpty {
      return entries[min(entries.count - 1, max(0, Int(pointerRow.rounded())))].id
    }
    return focusedEntryID
  }

  private func dismissPreview() {
    dismissedPreviewID = previewCandidateID
  }

  private func updatePointer(at y: CGFloat) {
    let row = y / ScholiumMetrics.Document.outlineMarkerTarget - 0.5
    pointerRow = row
    guard !entries.isEmpty else { return }
    let nearest = min(entries.count - 1, max(0, Int(row.rounded())))
    guard nearest != hapticRow else { return }
    // A little boundary hysteresis prevents repeated ticks when a finger
    // rests between two marks. Fast sweeps never queue delayed feedback.
    if let hapticRow, abs(row - CGFloat(hapticRow)) < 0.65 { return }
    hapticRow = nearest
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastHoverHapticTime >= ScholiumMetrics.Document.outlineHoverHapticInterval else {
      return
    }
    lastHoverHapticTime = now
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
  }

  private func interactionInfluence(at index: Int) -> CGFloat {
    let interactionRow =
      pointerRow ?? entries.firstIndex(where: { $0.id == focusedEntryID }).map(CGFloat.init)
    guard let interactionRow else { return 0 }
    let distance = abs(CGFloat(index) - interactionRow)
    let radius = ScholiumMetrics.Document.outlineMarkerHoverRadius
    guard distance < radius else { return 0 }
    // Continuous falloff has no steps at row boundaries and eases to zero
    // at the edge, so neighboring marks flow together as the pointer moves.
    return (1 + cos(.pi * distance / radius)) / 2
  }

  private func markerColor(isActive: Bool, influence: CGFloat) -> Color {
    let resting =
      increasedContrast
      ? ScholiumMetrics.Document.outlineMarkerIncreasedContrastRestingOpacity
      : ScholiumMetrics.Document.outlineMarkerRestingOpacity
    let hovered =
      increasedContrast
      ? ScholiumMetrics.Document.outlineMarkerIncreasedContrastHoverOpacity
      : ScholiumMetrics.Document.outlineMarkerHoverOpacity
    let active =
      increasedContrast
      ? ScholiumMetrics.Document.outlineMarkerIncreasedContrastActiveOpacity
      : ScholiumMetrics.Document.outlineMarkerActiveOpacity
    let opacity = max(isActive ? active : resting, resting + (hovered - resting) * influence)
    return ScholiumColorRole.primaryText.color(increasedContrast: increasedContrast)
      .opacity(opacity)
  }
}

private struct DocumentOutlineMarkerButtonStyle: ButtonStyle {
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(
        configuration.isPressed
          ? ScholiumMetrics.Document.outlineMarkerPressedOpacity
          : 1
      )
      .onChange(of: configuration.isPressed) { _, isPressed in
        guard isPressed else { return }
        // Play while the finger is still down: AppKit may suppress feedback
        // on release when a tap-to-click finger has already left the trackpad.
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
      }
      .animation(
        ScholiumMotion.disclosure(reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}

private struct DocumentOutlineMarkerBounds: PreferenceKey {
  static let defaultValue: [DocumentOutlineEntry.ID: Anchor<CGRect>] = [:]

  static func reduce(
    value: inout [DocumentOutlineEntry.ID: Anchor<CGRect>],
    nextValue: () -> [DocumentOutlineEntry.ID: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}
