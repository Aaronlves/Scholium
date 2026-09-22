import AppKit
import SwiftUI

private struct DocumentToolbarUnderlapKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var documentToolbarUnderlap: Bool {
        get { self[DocumentToolbarUnderlapKey.self] }
        set { self[DocumentToolbarUnderlapKey.self] = newValue }
    }
}

/// Native material confined to the part of a document actually behind window
/// chrome. It never paints the Paper reading area below contentLayoutRect.
final class DocumentToolbarTransition: NSVisualEffectView {
    private var maskHeight: CGFloat = -1

    init() {
        super.init(frame: .zero)
        material = .headerView
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        clipsToBounds = true
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(adaptationChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard maskHeight != bounds.height else { return }
        updateMask()
    }

    @objc private func adaptationChanged() { updateMask() }

    private func updateMask() {
        maskHeight = bounds.height
        let workspace = NSWorkspace.shared
        guard !workspace.accessibilityDisplayShouldReduceTransparency,
            !workspace.accessibilityDisplayShouldIncreaseContrast, bounds.height > 0
        else { maskImage = nil; return }
        maskImage = NSImage(size: NSSize(width: 1, height: bounds.height), flipped: false) { rect in
            guard let gradient = NSGradient(starting: .clear, ending: .black) else { return false }
            gradient.draw(in: rect, angle: 90)
            return true
        }
    }
}
