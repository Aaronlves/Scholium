import AppKit
import QuickLookUI
import ScholiumContracts

enum DocumentAttachmentSelectionMode: Equatable {
    case copyIntoTriptych
    case referenceOriginal
}

private final class DocumentAttachmentPreviewPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
private final class DocumentAttachmentMenuTarget: NSObject {
    let choose: (DocumentAttachmentSelectionMode) -> Void

    init(choose: @escaping (DocumentAttachmentSelectionMode) -> Void) {
        self.choose = choose
    }

    @objc func copyIntoTriptych() { choose(.copyIntoTriptych) }
    @objc func referenceOriginal() { choose(.referenceOriginal) }
}

@MainActor
func presentDocumentAttachmentMenu(
    clientX: Double,
    clientY: Double,
    in view: NSView,
    choose: @escaping (DocumentAttachmentSelectionMode) -> Void
) {
    guard clientX.isFinite, clientY.isFinite else { return }
    let target = DocumentAttachmentMenuTarget(choose: choose)
    let menu = NSMenu(title: "")
    let copy = NSMenuItem(
        title: String(localized: "Attach a Copy…"),
        action: #selector(DocumentAttachmentMenuTarget.copyIntoTriptych),
        keyEquivalent: ""
    )
    copy.target = target
    let reference = NSMenuItem(
        title: String(localized: "Reference Original…"),
        action: #selector(DocumentAttachmentMenuTarget.referenceOriginal),
        keyEquivalent: ""
    )
    reference.target = target
    menu.items = [copy, reference]
    menu.popUp(
        positioning: nil,
        at: NSPoint(x: clientX, y: view.bounds.height - clientY),
        in: view
    )
}

/// Owns one native Quick Look surface and the exact security-scope lease that
/// keeps an original referenced document readable for the panel's lifetime.
@MainActor
final class DocumentAttachmentQuickLookPresenter: NSObject, ObservableObject,
    NSWindowDelegate
{
    private var windowController: NSWindowController?
    private var previewView: QLPreviewView?
    private var lease: DocumentAttachmentPreviewLease?
    private var releaseAccess: ((UUID) async -> Void)?
    private var restoreFocus: (() -> Void)?

    func present(
        _ lease: DocumentAttachmentPreviewLease,
        releaseAccess: @escaping (UUID) async -> Void,
        restoreFocus: @escaping () -> Void
    ) {
        dismissCurrent(restoringFocus: false)

        guard let preview = QLPreviewView(frame: .zero, style: .normal) else {
            Task { await releaseAccess(lease.accessToken) }
            restoreFocus()
            return
        }
        preview.autostarts = false
        preview.shouldCloseWithWindow = true
        preview.previewItem = lease.fileURL as NSURL

        let panel = DocumentAttachmentPreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = lease.filename
        panel.minSize = NSSize(width: 480, height: 360)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = preview
        panel.center()

        self.lease = lease
        self.releaseAccess = releaseAccess
        self.restoreFocus = restoreFocus
        previewView = preview
        windowController = NSWindowController(window: panel)
        windowController?.showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        dismissCurrent(restoringFocus: true)
    }

    func windowWillClose(_ notification: Notification) {
        finishPresentation(restoringFocus: true)
    }

    private func dismissCurrent(restoringFocus: Bool) {
        guard lease != nil || windowController != nil else { return }
        windowController?.window?.delegate = nil
        windowController?.close()
        finishPresentation(restoringFocus: restoringFocus)
    }

    private func finishPresentation(restoringFocus: Bool) {
        let token = lease?.accessToken
        let release = releaseAccess
        let focus = restoreFocus
        previewView?.close()
        previewView = nil
        windowController = nil
        lease = nil
        releaseAccess = nil
        restoreFocus = nil
        if let token, let release {
            Task { await release(token) }
        }
        if restoringFocus {
            Task { @MainActor in
                await Task.yield()
                focus?()
            }
        }
    }
}
