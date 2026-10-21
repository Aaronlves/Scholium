import AppKit
import ScholiumContracts
import SwiftUI

enum DocumentSurfaceVisibility: Equatable {
    case active
    case preparing
    case retained

    var isActive: Bool {
        self == .active
    }
}

private struct ScholiumDocumentSurfaceVisibilityKey: EnvironmentKey {
    static let defaultValue = DocumentSurfaceVisibility.active
}

extension EnvironmentValues {
    var scholiumDocumentSurfaceVisibility: DocumentSurfaceVisibility {
        get { self[ScholiumDocumentSurfaceVisibilityKey.self] }
        set { self[ScholiumDocumentSurfaceVisibilityKey.self] = newValue }
    }
}

/// Owns the shared host's acknowledgement and recovery handoff. Initial
/// presentation waits for the requested bridge mode; a previously presented
/// CodeMirror surface can stay visible during an atomic mode reconfiguration.
struct DocumentEditorPresentationGate: Equatable {
    private(set) var presentedDocumentID: String?

    mutating func reconcile(documentID: String, editorIsReady: Bool) {
        if editorIsReady {
            presentedDocumentID = documentID
        }
    }

    mutating func reset() {
        presentedDocumentID = nil
    }

    func showsEditor(documentID: String, editorIsLoaded: Bool, editorIsReady: Bool) -> Bool {
        editorIsLoaded && (presentedDocumentID == documentID || editorIsReady)
    }

    func allowsRecoveryHitTesting(editorIsLoaded: Bool, editorIsReady: Bool) -> Bool {
        !editorIsLoaded || !editorIsReady
    }

    func allowsEditorFocus(
        isEditing: Bool,
        isReturningToReview: Bool,
        editorIsReady: Bool,
        presentedModeMatchesIntent: Bool
    ) -> Bool {
        isEditing
            && !isReturningToReview
            && editorIsReady
            && presentedModeMatchesIntent
    }
}

/// Owns visibility and input eligibility while a document projection prepares.
/// A retained host keeps its source, selection, composition, and Undo live;
/// callers choose whether a previously presented projection can remain visible.
struct DocumentEditorHost<RecoverySurface: View, EditorSurface: View>: View {
    let documentID: String
    let retainsEditor: Bool
    let editorIsLoaded: Bool
    let editorIsReady: Bool
    let keepsPresentedSurfaceWhilePreparing: Bool
    let presentsRecovery: Bool
    let preparationTitle: String
    let preparationPresentation: ScholiumDocumentPresentationConfiguration
    let preparationAppearance: DocumentAppearanceSettings
    private let recoverySurface: RecoverySurface
    private let editorSurface: EditorSurface
    @State private var presentationGate = DocumentEditorPresentationGate()

    init(
        documentID: String,
        retainsEditor: Bool,
        editorIsLoaded: Bool,
        editorIsReady: Bool,
        keepsPresentedSurfaceWhilePreparing: Bool = true,
        presentsRecovery: Bool = false,
        preparationTitle: String = "",
        preparationPresentation: ScholiumDocumentPresentationConfiguration = .init(textScale: 1),
        preparationAppearance: DocumentAppearanceSettings = .defaultSettings,
        @ViewBuilder recovery: () -> RecoverySurface,
        @ViewBuilder editor: () -> EditorSurface
    ) {
        self.documentID = documentID
        self.retainsEditor = retainsEditor
        self.editorIsLoaded = editorIsLoaded
        self.editorIsReady = editorIsReady
        self.keepsPresentedSurfaceWhilePreparing = keepsPresentedSurfaceWhilePreparing
        self.presentsRecovery = presentsRecovery
        self.preparationTitle = preparationTitle
        self.preparationPresentation = preparationPresentation
        self.preparationAppearance = preparationAppearance
        recoverySurface = recovery()
        editorSurface = editor()
    }

    private var showsEditor: Bool {
        !presentsRecovery
            && (keepsPresentedSurfaceWhilePreparing || editorIsReady)
            && presentationGate.showsEditor(
                documentID: documentID,
                editorIsLoaded: editorIsLoaded,
                editorIsReady: editorIsReady
            )
    }

    var body: some View {
        ZStack {
            if presentsRecovery {
                recoverySurface
                    .environment(\.scholiumDocumentSurfaceVisibility, .active)
                    .allowsHitTesting(
                        presentationGate.allowsRecoveryHitTesting(
                            editorIsLoaded: editorIsLoaded,
                            editorIsReady: editorIsReady
                        )
                    )
                    .accessibilityHidden(false)
                    .zIndex(showsEditor ? 0 : 1)
            }

            if retainsEditor {
                editorSurface
                    .environment(
                        \.scholiumDocumentSurfaceVisibility,
                        showsEditor
                            ? .active
                            : presentsRecovery ? .retained : .preparing
                    )
                    .allowsHitTesting(showsEditor)
                    .accessibilityHidden(!showsEditor)
                    .zIndex(showsEditor ? 1 : 0)
            }
            if !showsEditor && !presentsRecovery {
                DocumentPreparationStatus(
                    title: preparationTitle,
                    identifier: "scholium.documentPreparing",
                    presentation: preparationPresentation,
                    appearance: preparationAppearance
                )
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
        .onChange(of: documentID) { _, _ in
            presentationGate.reconcile(documentID: documentID, editorIsReady: editorIsReady)
        }
        .onAppear {
            presentationGate.reconcile(
                documentID: documentID,
                editorIsReady: editorIsReady
            )
        }
        .onChange(of: presentsRecovery) { _, showsRecovery in
            if showsRecovery {
                presentationGate.reset()
            }
        }
        .onChange(of: editorIsReady) { _, _ in
            presentationGate.reconcile(
                documentID: documentID,
                editorIsReady: editorIsReady
            )
        }
    }
}

/// One native cover spans the entire preparation lifecycle, including the
/// WebKit bootstrap before any document exists. The renderer underneath keeps
/// its real viewport for measurement; only acknowledged content is revealed.
struct DocumentPreparationStatus: View {
    let title: String
    var identifier = "scholium.documentPreparing"
    var presentation = ScholiumDocumentPresentationConfiguration(textScale: 1)
    var appearance = DocumentAppearanceSettings.defaultSettings
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    @Environment(\.documentToolbarUnderlap) private var toolbarUnderlap

    var body: some View {
        DocumentPreparationDrawing(
            presentation: presentation,
            appearance: appearance,
            toolbarUnderlap: toolbarUnderlap,
            increasedContrast: increasedContrast
        )
        .modifier(ResearchSkeletonPulse(isActive: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScholiumColorRole.documentBackground.color)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? Text("Loading Document…") : Text("Opening \(title)…"))
        .accessibilityIdentifier(identifier)
    }
}

private struct DocumentPreparationDrawing: NSViewRepresentable {
    let presentation: ScholiumDocumentPresentationConfiguration
    let appearance: DocumentAppearanceSettings
    let toolbarUnderlap: Bool
    let increasedContrast: Bool

    func makeNSView(context: Context) -> DocumentPreparationDrawingView {
        DocumentPreparationDrawingView()
    }

    func updateNSView(_ view: DocumentPreparationDrawingView, context: Context) {
        view.presentation = presentation
        view.documentAppearance = appearance
        view.toolbarUnderlap = toolbarUnderlap
        view.increasedContrast = increasedContrast
        view.needsDisplay = true
    }
}

/// A fixed title, property rows and paragraphs, clipped to the real viewport.
/// Only appearance and chrome geometry are inputs; note contents never are.
final class DocumentPreparationDrawingView: NSView {
    var presentation = ScholiumDocumentPresentationConfiguration(textScale: 1)
    var documentAppearance = DocumentAppearanceSettings.defaultSettings
    var toolbarUnderlap = false
    var increasedContrast = false
    private var chromeObservation: NSKeyValueObservation?
    override var isFlipped: Bool { true }

    var documentColumn: NSRect {
        let fontSize = documentAppearance.body.fontSizePoints * (96.0 / 72.0) * presentation.textScale
        let characterWidth = DocumentAppearanceStyles.zeroCharacterWidth(for: documentAppearance.body, textScale: presentation.textScale)
        let minimumInset =
            bounds.width <= presentation.compactThresholdRootEms * 16
            ? presentation.compactInlineInsetCSSPixels : presentation.regularInlineInsetCSSPixels
        let inset = max(minimumInset, (bounds.width - documentAppearance.lineWidthCharacterUnits * characterWidth) / 2)
        let toolbarInset = toolbarUnderlap ? DocumentViewportGeometry.toolbarOverlap(in: self).height : 0
        let top = presentation.contentTopInsetCSSPixels + toolbarInset + fontSize * ScholiumDocumentRhythm.readingTopGapEms
        return NSRect(x: bounds.minX + inset, y: bounds.minY + top, width: max(0, bounds.width - inset * 2), height: max(0, bounds.height - top))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        chromeObservation = window?.observe(\.contentLayoutRect, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let column = documentColumn
        guard column.width > 0 else { return }
        ScholiumColorRole.secondaryText.nsColor(increasedContrast: increasedContrast)
            .withAlphaComponent(increasedContrast ? 0.4 : 0.25).setFill()
        let fontSize = documentAppearance.body.fontSizePoints * (96.0 / 72.0) * presentation.textScale
        let lineHeight = fontSize * documentAppearance.body.lineHeight
        let barHeight = fontSize * 0.65
        let titleSize = fontSize * ScholiumDocumentRhythm.titleScale
        var y = column.minY
        func bar(_ widthFraction: CGFloat, height: CGFloat, top: CGFloat) {
            NSBezierPath(
                roundedRect: NSRect(x: column.minX, y: top, width: column.width * widthFraction, height: height),
                xRadius: ScholiumGrid.foundationUnit / 2, yRadius: ScholiumGrid.foundationUnit / 2
            ).fill()
        }
        bar(0.58, height: titleSize * 0.75, top: y + titleSize * 0.15)
        y += titleSize * (ScholiumDocumentRhythm.titleLineHeight + ScholiumDocumentRhythm.titleAfterEms)
        for property in 0..<3 {
            bar(property == 1 ? 0.36 : 0.48, height: barHeight, top: y + (lineHeight - barHeight) / 2)
            y += lineHeight
        }
        y += fontSize * documentAppearance.body.paragraphSpacingEm
        var paragraph = 0
        while y < bounds.maxY {
            if paragraph.isMultiple(of: 2) {
                y += fontSize
                bar(0.32, height: fontSize, top: y)
                y += lineHeight * 1.5
            }
            for line in 0..<4 {
                bar(line == 3 ? 0.66 : line == 1 ? 0.94 : 1, height: barHeight, top: y + (lineHeight - barHeight) / 2)
                y += lineHeight
            }
            y += fontSize * documentAppearance.body.paragraphSpacingEm
            paragraph += 1
        }
    }
}
