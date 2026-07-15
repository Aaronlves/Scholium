import ScholiumContracts
import AppKit
import SwiftUI

/// Fires after AppKit lays out the SwiftUI subtree for one generation. This is
/// a measurement boundary, not a visible view or a product-state authority.
struct PerformanceReadyBoundary: NSViewRepresentable {
    let generation: String
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> BoundaryView {
        BoundaryView(generation: generation, action: action)
    }

    func updateNSView(_ view: BoundaryView, context: Context) {
        view.update(generation: generation, action: action)
    }

    @MainActor
    final class BoundaryView: NSView {
        private var generation: String
        private var completedGeneration: String?
        private var action: @MainActor () -> Void

        init(generation: String, action: @escaping @MainActor () -> Void) {
            self.generation = generation
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(generation: String, action: @escaping @MainActor () -> Void) {
            self.generation = generation
            self.action = action
            needsLayout = true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            completeIfNeeded()
        }

        override func layout() {
            super.layout()
            completeIfNeeded()
        }

        private func completeIfNeeded() {
            guard window != nil, completedGeneration != generation else { return }
            completedGeneration = generation
            action()
        }
    }
}
