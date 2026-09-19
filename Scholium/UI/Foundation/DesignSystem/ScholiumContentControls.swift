import AppKit
import SwiftUI

private struct ScholiumContentControlIsEmphasizedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scholiumContentControlIsEmphasized: Bool {
        get { self[ScholiumContentControlIsEmphasizedKey.self] }
        set { self[ScholiumContentControlIsEmphasizedKey.self] = newValue }
    }
}

private struct ScholiumContentControlInkModifier: ViewModifier {
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized

    let restingRole: ScholiumColorRole
    let emphasizedRole: ScholiumColorRole

    func body(content: Content) -> some View {
        content.foregroundStyle(
            (isEmphasized ? emphasizedRole : restingRole).color
        )
    }
}

/// The shared transient-state owner for custom SwiftUI Buttons. Native Menu
/// labels use the AppKit tracking adapter below because SwiftUI does not
/// reliably forward their pointer state. Ordinary Buttons use SwiftUI's
/// lightweight hover and ButtonStyle press path; native-container call sites
/// may leave hover to AppKit while retaining the shared press path.
private struct ScholiumHoverStateModifier: ViewModifier {
    let tracksHover: Bool
    let stateDidChange: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if tracksHover {
            content.onHover(perform: stateDidChange)
        } else {
            content
        }
    }
}

private struct ScholiumContentControlButtonFeedbackModifier<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var observedHovering = false

    let isActive: Bool
    let isSelected: Bool
    let isFocused: Bool
    let isPressed: Bool
    let hoverOverride: Bool?
    let tracksHover: Bool
    let pressedOpacity: Double
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        let effectiveIsHovering = hoverOverride ?? (tracksHover && observedHovering)
        let hasTransientEmphasis =
            isEnabled && (effectiveIsHovering || isFocused || isPressed)
        let isEmphasized = isActive || isSelected || hasTransientEmphasis

        let feedback =
            content
            .environment(\.scholiumContentControlIsEmphasized, isEmphasized)
            .scholiumContentInteractionSurface(
                isSelected: isSelected,
                isHovering: effectiveIsHovering,
                isFocused: isFocused,
                isPressed: isPressed,
                in: shape
            )
            .opacity(isEnabled && isPressed ? pressedOpacity : 1)

        feedback.modifier(
            ScholiumHoverStateModifier(
                tracksHover: hoverOverride == nil && tracksHover,
                stateDidChange: { observedHovering = $0 }
            )
        )
    }
}

/// Applies the product's activation cursor only to controls that perform a
/// discrete click action. Text entry, selection, dragging, and resizing retain
/// their native semantic cursors.
private struct ScholiumActivationPointerModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : .default)
    }
}

/// AppKit counterpart to `scholiumActivationPointer()`. Use it for explicit
/// Scholium-owned buttons hosted outside SwiftUI; native text, drag, and split
/// controls continue to own their own cursor rects.
@MainActor
class ScholiumPointingHandButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(
            bounds,
            cursor: isEnabled ? .pointingHand : .arrow
        )
    }
}

/// Shared ButtonStyle for content controls. Leave `isHovering` nil for local
/// button tracking; supply it when a surrounding custom control already owns
/// the pointer region used by its auxiliary state.
struct ScholiumContentControlButtonStyle<S: Shape>: ButtonStyle {
    let isActive: Bool
    let isSelected: Bool
    let isFocused: Bool
    let isHovering: Bool?
    let tracksHover: Bool
    let pressedOpacity: Double
    let shape: S

    init(
        isActive: Bool = false,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isHovering: Bool? = nil,
        tracksHover: Bool = true,
        pressedOpacity: Double = 0.78,
        in shape: S
    ) {
        self.isActive = isActive
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isHovering = isHovering
        self.tracksHover = tracksHover
        self.pressedOpacity = pressedOpacity
        self.shape = shape
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scholiumContentControlButtonFeedback(
                isActive: isActive,
                isSelected: isSelected,
                isFocused: isFocused,
                isPressed: configuration.isPressed,
                isHovering: isHovering,
                tracksHover: tracksHover,
                pressedOpacity: pressedOpacity,
                in: shape
            )
    }
}

/// A zero-hit-test AppKit observer for the complete control frame. SwiftUI's
/// native Menu host does not reliably forward pointer state to its label, so
/// the presentation adapter observes tracking and button events without
/// intercepting or replacing the native control's activation.
private struct ScholiumPointerInteractionReader: NSViewRepresentable {
    @Binding var isHovering: Bool
    @Binding var isPressed: Bool

    func makeNSView(context: Context) -> ScholiumPointerTrackingView {
        let view = ScholiumPointerTrackingView()
        view.stateDidChange = updateState
        return view
    }

    func updateNSView(_ view: ScholiumPointerTrackingView, context: Context) {
        view.stateDidChange = updateState
    }

    static func dismantleNSView(
        _ view: ScholiumPointerTrackingView,
        coordinator: Void
    ) {
        view.invalidate()
    }

    private func updateState(isHovering: Bool, isPressed: Bool) {
        self.isHovering = isHovering
        self.isPressed = isPressed
    }
}

final class ScholiumPointerTrackingView: NSView {
    var stateDidChange: ((Bool, Bool) -> Void)?

    private var pointerIsInside = false
    private var pointerIsPressed = false
    private var localEventMonitor: Any?
    private var controlTrackingArea: NSTrackingArea?
    private weak var observedClipView: NSClipView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // AppKit's unclipped visibleRect may extend to the parent viewport.
        // This observation-only view must track precisely its own control.
        clipsToBounds = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows clipping and scrolling without replacing the
        // tracking identity (and losing the matching exit event) on every layout.
        if controlTrackingArea == nil {
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            controlTrackingArea = area
            addTrackingArea(area)
        }
        observeViewport()
        synchronizePointerWithWindow()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeLocalEventMonitor()
        NotificationCenter.default.removeObserver(self)
        observedClipView = nil
        guard let window else { return }
        observeViewport()
        for name in [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowActivityChanged), name: name, object: window)
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handlePointerEvent(event)
            return event
        }
    }

    override func mouseEntered(with event: NSEvent) {
        synchronizePointerWithWindow()
    }

    override func mouseExited(with event: NSEvent) {
        setState(isHovering: false, isPressed: false)
    }

    func invalidate() {
        removeLocalEventMonitor()
        NotificationCenter.default.removeObserver(self)
        stateDidChange = nil
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard let window, event.window === window else {
            setState(isHovering: false, isPressed: false)
            return
        }
        let isInside = bounds.intersection(visibleRect).contains(convert(event.locationInWindow, from: nil))
        switch event.type {
        case .mouseMoved:
            synchronizePointer(locationInWindow: window.isKeyWindow ? event.locationInWindow : nil)
        case .leftMouseDown:
            guard isInside else { return }
            setState(isHovering: true, isPressed: true)
        case .leftMouseDragged:
            guard pointerIsPressed else { return }
            setState(isHovering: isInside, isPressed: isInside)
        case .leftMouseUp:
            guard pointerIsPressed else { return }
            setState(isHovering: isInside, isPressed: false)
        default:
            break
        }
    }

    private func setState(isHovering: Bool, isPressed: Bool) {
        guard pointerIsInside != isHovering || pointerIsPressed != isPressed else {
            return
        }
        pointerIsInside = isHovering
        pointerIsPressed = isPressed
        stateDidChange?(isHovering, isPressed)
    }

    private func removeLocalEventMonitor() {
        guard let localEventMonitor else { return }
        NSEvent.removeMonitor(localEventMonitor)
        self.localEventMonitor = nil
        setState(isHovering: false, isPressed: false)
    }

    private func observeViewport() {
        let clip = enclosingScrollView?.contentView
        guard observedClipView !== clip else { return }
        if let observedClipView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedClipView = clip
        if let clip {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    @objc private func viewportChanged(_ notification: Notification) {
        synchronizePointerWithWindow()
    }

    @objc private func windowActivityChanged(_ notification: Notification) {
        synchronizePointerWithWindow()
    }

    private func synchronizePointerWithWindow() {
        synchronizePointer(
            locationInWindow: window?.isKeyWindow == true
                ? window?.mouseLocationOutsideOfEventStream : nil)
    }

    /// Geometry is current truth; an old enter event is not durable hover state.
    func synchronizePointer(locationInWindow: NSPoint?) {
        let inside =
            window != nil && !isHiddenOrHasHiddenAncestor
            && locationInWindow.map { bounds.intersection(visibleRect).contains(convert($0, from: nil)) } == true
        setState(isHovering: inside, isPressed: inside && pointerIsPressed)
    }

    isolated deinit {
        stateDidChange = nil
        removeLocalEventMonitor()
        NotificationCenter.default.removeObserver(self)
    }
}

/// One pointer-state owner for matching Scholium content controls. It keeps
/// hover and press capture, semantic ink promotion, shared surface paint, and
/// immediate press dimming identical whether a native Button or Menu owns the
/// actual activation.
private struct ScholiumContentControlPointerFeedbackModifier<S: Shape>: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var isPressed = false

    let isActive: Bool
    let isFocused: Bool
    let shape: S

    func body(content: Content) -> some View {
        let isEmphasized =
            isEnabled
            && (isActive || isHovering || isFocused || isPressed)

        content
            .environment(\.scholiumContentControlIsEmphasized, isEmphasized)
            .scholiumContentInteractionSurface(
                isHovering: isHovering,
                isFocused: isFocused,
                isPressed: isPressed,
                in: shape
            )
            .opacity(isEnabled && isPressed ? 0.78 : 1)
            .overlay {
                ScholiumPointerInteractionReader(
                    isHovering: $isHovering,
                    isPressed: $isPressed
                )
                .accessibilityHidden(true)
            }
    }
}

/// Keeps controls in the complete keyboard focus chain. Custom content
/// surfaces clear pointer-manufactured keyboard focus before painting their
/// own focus treatment; native buttons keep AppKit's unmodified pointer,
/// keyboard, and focus behavior.
enum ScholiumActivationFocusPresentation: Sendable {
    case contentSurface
    case native
}

private struct ScholiumBooleanActivationFocusModifier: ViewModifier {
    let focus: FocusState<Bool>.Binding
    let presentation: ScholiumActivationFocusPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .contentSurface:
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focus)
                .simultaneousGesture(pointerFocusReset)
        case .native:
            content
                .focusable()
                .focused(focus)
        }
    }

    private var pointerFocusReset: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in focus.wrappedValue = false }
            .onEnded { _ in focus.wrappedValue = false }
    }
}

private struct ScholiumValueActivationFocusModifier<Value: Hashable>: ViewModifier {
    let focus: FocusState<Value?>.Binding
    let value: Value
    let presentation: ScholiumActivationFocusPresentation

    @ViewBuilder
    func body(content: Content) -> some View {
        switch presentation {
        case .contentSurface:
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focus, equals: value)
                .simultaneousGesture(pointerFocusReset)
        case .native:
            content
                .focusable()
                .focused(focus, equals: value)
        }
    }

    private var pointerFocusReset: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in clearPointerFocus() }
            .onEnded { _ in clearPointerFocus() }
    }

    private func clearPointerFocus() {
        guard focus.wrappedValue == value else { return }
        focus.wrappedValue = nil
    }
}

/// Keeps short floating surfaces at their natural width while still wrapping
/// long content inside the window's available width and a semantic upper cap.
private struct ScholiumContentFittingWidthLayout: Layout {
    let maximumWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let availableWidth = min(proposal.width ?? maximumWidth, maximumWidth)
        let ideal = subview.sizeThatFits(
            ProposedViewSize(width: availableWidth, height: nil)
        )
        let width = min(ideal.width, availableWidth)
        let fitted = subview.sizeThatFits(
            ProposedViewSize(width: width, height: nil)
        )
        return CGSize(width: width, height: fitted.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: bounds.height
            )
        )
    }
}

/// A native Liquid Glass icon control for permanent commands in content-owned
/// chrome. The label keeps Scholium's semantic ink while the system owns shape,
/// hover, press, focus, active-window, and transparency adaptation. The outer
/// 28pt frame preserves the established target and neighboring layout.
struct ScholiumInkIconControl: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let identifier: String
    var isActive = false
    var symbolVerticalOffset: CGFloat = 0
    var role: ButtonRole? = nil
    var emphasizedColorRole: ScholiumColorRole = .primaryText
    var focus: FocusState<Bool>.Binding? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .offset(y: symbolVerticalOffset)
                .frame(
                    width: ScholiumMetrics.Accessibility.minimumCustomTarget,
                    height: ScholiumMetrics.Accessibility.minimumCustomTarget
                )
                .contentShape(Rectangle())
                .scholiumContentControlInk(
                    resting: .secondaryText,
                    emphasized: emphasizedColorRole
                )
                .opacity(isEnabled ? 1 : 0.42)
        }
        .scholiumIconControl()
        .environment(\.scholiumContentControlIsEmphasized, isActive)
        .modifier(ScholiumInkIconFocusModifier(externalFocus: focus))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

private struct ScholiumInkIconFocusModifier: ViewModifier {
    let externalFocus: FocusState<Bool>.Binding?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let externalFocus {
            content.focused(externalFocus)
        } else {
            content
        }
    }
}

extension View {
    /// Fits compact overlays and banners to their content without allowing
    /// authored or diagnostic text to escape the containing window.
    func scholiumContentFittingWidth(maximumWidth: CGFloat) -> some View {
        ScholiumContentFittingWidthLayout(maximumWidth: maximumWidth) {
            self
        }
    }

    /// Reports SwiftUI pointer presence through the Design System's single
    /// hover adapter. Feature views may retain semantic reveal state, but do
    /// not own a second platform presentation path.
    func scholiumHoverState(
        tracksHover: Bool = true,
        _ stateDidChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            ScholiumHoverStateModifier(
                tracksHover: tracksHover,
                stateDidChange: stateDidChange
            )
        )
    }

    /// Uses the pointing hand for one enabled discrete activation target while
    /// retaining the arrow for its unavailable state.
    func scholiumActivationPointer() -> some View {
        modifier(ScholiumActivationPointerModifier())
    }

    /// Applies the shared pointer-neutral, keyboard-complete focus policy to a
    /// custom button-like control with Boolean focus state.
    func scholiumActivationFocus(
        _ focus: FocusState<Bool>.Binding,
        presentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        modifier(
            ScholiumBooleanActivationFocusModifier(
                focus: focus,
                presentation: presentation
            ))
    }

    /// Applies the same policy to one value in a focusable control group.
    func scholiumActivationFocus<Value: Hashable>(
        _ focus: FocusState<Value?>.Binding,
        equals value: Value,
        presentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        modifier(
            ScholiumValueActivationFocusModifier(
                focus: focus,
                value: value,
                presentation: presentation
            ))
    }

    /// Applies the complete shared SwiftUI Button presentation while the
    /// Button retains activation, keyboard focus, and accessibility semantics.
    func scholiumContentControlButtonFeedback<S: Shape>(
        isActive: Bool = false,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isPressed: Bool,
        isHovering: Bool? = nil,
        tracksHover: Bool = true,
        pressedOpacity: Double = 0.78,
        in shape: S
    ) -> some View {
        modifier(
            ScholiumContentControlButtonFeedbackModifier(
                isActive: isActive,
                isSelected: isSelected,
                isFocused: isFocused,
                isPressed: isPressed,
                hoverOverride: isHovering,
                tracksHover: tracksHover,
                pressedOpacity: pressedOpacity,
                shape: shape
            )
        )
    }

    func scholiumContentControlInk(
        resting restingRole: ScholiumColorRole = .secondaryText,
        emphasized emphasizedRole: ScholiumColorRole = .primaryText
    ) -> some View {
        modifier(
            ScholiumContentControlInkModifier(
                restingRole: restingRole,
                emphasizedRole: emphasizedRole
            )
        )
    }

    /// Applies the complete shared pointer presentation to a matching custom
    /// content control while the enclosing native control retains activation,
    /// keyboard focus, menus, and accessibility.
    func scholiumContentControlPointerFeedback<S: Shape>(
        isActive: Bool = false,
        isFocused: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            ScholiumContentControlPointerFeedbackModifier(
                isActive: isActive,
                isFocused: isFocused,
                shape: shape
            ))
    }
}
