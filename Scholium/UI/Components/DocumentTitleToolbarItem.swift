import AppKit
import ScholiumContracts

/// Native chrome owns filename presentation; the window's existing file
/// operation owns renaming. The popover never edits Markdown or moves files.
@MainActor
final class DocumentTitleToolbarItem: NSToolbarItem, NSPopoverDelegate {
    private weak var model: WindowModel?
    private let titleButton = NSButton()
    private let popover = NSPopover()
    private var targetKey: DocumentSessionKey?
    private var presentationID: UUID?
    private var editor: DocumentTitlePopoverController?
    private weak var presentingWindow: NSWindow?
    private weak var previousResponder: NSResponder?

    init(identifier: NSToolbarItem.Identifier, model: WindowModel) {
        self.model = model
        super.init(itemIdentifier: identifier)
        label = ScholiumL10n.string("Note title")
        paletteLabel = label
        visibilityPriority = .high
        titleButton.bezelStyle = .accessoryBarAction
        titleButton.isBordered = false
        titleButton.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        titleButton.imagePosition = .imageTrailing
        titleButton.cell?.lineBreakMode = .byTruncatingMiddle
        titleButton.target = self
        titleButton.action = #selector(toggleTitle(_:))
        titleButton.setAccessibilityIdentifier("scholium.document.title")
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleButton.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            titleButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
        view = titleButton
        target = self
        action = #selector(toggleTitle(_:))
        let overflow = NSMenuItem(title: label, action: #selector(toggleTitle(_:)), keyEquivalent: "")
        overflow.target = self
        menuFormRepresentation = overflow
        popover.behavior = .transient
        popover.delegate = self
        refreshPresentation()
    }

    override func validate() { refreshPresentation() }

    func refreshPresentation() {
        let note = model?.currentNote
        let name = note?.displayName ?? ""
        titleButton.title = name
        titleButton.toolTip = name
        titleButton.setAccessibilityLabel(ScholiumL10n.string("Note title"))
        titleButton.setAccessibilityValue(name)
        titleButton.setAccessibilityHelp(ScholiumL10n.string("Rename Note…"))
        isHidden = note == nil
        isEnabled = model?.canPerformNoteAction(.rename) == true
        titleButton.isEnabled = isEnabled
        menuFormRepresentation?.title = name
        menuFormRepresentation?.isEnabled = isEnabled
        if targetKey != model?.documentController.selectedDocument?.sessionKey {
            discardPresentation()
        } else {
            editor?.updateAuthoritativeName(name)
        }
    }

    func show(in window: NSWindow? = nil) {
        refreshPresentation()
        guard isEnabled, let model, let note = model.currentNote,
            let key = model.documentController.selectedDocument?.sessionKey,
            let window = window ?? titleButton.window
        else { return }
        if popover.isShown { return }
        if editor == nil {
            let presentationID = UUID()
            self.presentationID = presentationID
            let controller = DocumentTitlePopoverController(
                name: note.displayName, location: note.relativePath,
                rename: { [weak model] expected, requested in
                    guard let model, model.documentController.selectedDocument?.sessionKey == key else {
                        throw DocumentTitleRenameError.noteUnavailable
                    }
                    return try await model.renameDocumentTitle(
                        requestedNote: note, expectedTitle: expected, requestedTitle: requested)
                },
                latestName: { [weak model] in model?.currentNote?.displayName },
                dismiss: { [weak self] in
                    guard self?.presentationID == presentationID else { return }
                    self?.discardPresentation()
                })
            controller.onSizeChange = { [weak self] size in
                guard self?.presentationID == presentationID else { return }
                self?.popover.contentSize = size
            }
            editor = controller
            targetKey = key
            controller.prepareForPresentation(in: popover)
        }
        presentingWindow = window
        previousResponder = window.firstResponder
        if toolbar?.isVisible == true {
            popover.show(relativeTo: self)
        } else if let content = window.contentView {
            // The File menu remains usable while Focus Layout hides chrome.
            let safe = content.safeAreaRect
            popover.show(
                relativeTo: Self.fallbackAnchor(in: safe, isFlipped: content.isFlipped),
                of: content, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        editor?.focusName()
    }

    static func fallbackAnchor(in rect: NSRect, isFlipped: Bool) -> NSRect {
        let width = min(1, rect.width)
        let height = min(1, rect.height)
        return NSRect(
            x: rect.midX - width / 2,
            y: isFlipped ? rect.minY : rect.maxY - height,
            width: width, height: height)
    }

    @objc private func toggleTitle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { show() }
    }

    private func discardPresentation() {
        popover.close()
        editor = nil
        targetKey = nil
        presentationID = nil
        popover.contentViewController = nil
    }

    func invalidate() {
        model = nil
        previousResponder = nil
        discardPresentation()
        titleButton.target = nil
        titleButton.isEnabled = false
        menuFormRepresentation = nil
        isEnabled = false
    }

    func popoverDidClose(_ notification: Notification) {
        // Outside clicks retain a draft for reopening; explicit Cancel and a
        // successful Rename discard it. They never implicitly rename a file.
        if let window = presentingWindow, window.isKeyWindow, let previousResponder {
            if let view = previousResponder as? NSView, view.window !== window { return }
            window.makeFirstResponder(previousResponder)
        }
        previousResponder = nil
    }
}

@MainActor
final class DocumentTitlePopoverController: NSViewController, NSTextFieldDelegate {
    let nameField = NSTextField(string: "")
    var onSizeChange: ((NSSize) -> Void)?
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let renameButton = NSButton()
    private var expectedName: String
    private var currentName: String
    private let location: String
    private let rename: (String, String) async throws -> String
    private let latestName: () -> String?
    private let dismiss: () -> Void
    private var renameTask: Task<Void, Never>?

    init(
        name: String, location: String,
        rename: @escaping (String, String) async throws -> String,
        latestName: @escaping () -> String?, dismiss: @escaping () -> Void
    ) {
        expectedName = name
        currentName = name
        self.location = location
        self.rename = rename
        self.latestName = latestName
        self.dismiss = dismiss
        super.init(nibName: nil, bundle: nil)
        nameField.stringValue = name
    }

    required init?(coder: NSCoder) { fatalError("Constructed with a Note") }

    override func loadView() {
        view = NSView()
        nameField.delegate = self
        // Leaving or selecting the field is not an explicit rename. Return
        // and the Rename button retain their normal target/action route.
        nameField.cell?.sendsActionOnEndEditing = false
        nameField.target = self
        nameField.action = #selector(submit(_:))
        nameField.setAccessibilityLabel(ScholiumL10n.string("Note title"))
        nameField.setAccessibilityIdentifier("scholium.document.rename.name")
        let locationLabel = NSTextField(labelWithString: location)
        locationLabel.lineBreakMode = .byTruncatingMiddle
        locationLabel.toolTip = location
        locationLabel.textColor = .secondaryLabelColor
        let nameLabel = NSTextField(labelWithString: ScholiumL10n.string("Name"))
        let locationTitle = NSTextField(labelWithString: ScholiumL10n.string("Location"))
        let grid = NSGridView(views: [
            [nameLabel, nameField], [locationTitle, locationLabel],
        ])
        grid.column(at: 0).width = max(nameLabel.intrinsicContentSize.width, locationTitle.intrinsicContentSize.width)
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = ScholiumGrid.Spacing.inlineControlGap
        errorLabel.textColor = .labelColor
        errorLabel.isHidden = true
        errorLabel.setAccessibilityIdentifier("scholium.document.rename.error")
        renameButton.title = ScholiumL10n.string("Rename")
        renameButton.bezelStyle = .rounded
        renameButton.target = self
        renameButton.action = #selector(submit(_:))
        renameButton.keyEquivalent = "\r"
        let cancel = NSButton(title: ScholiumL10n.string("Cancel"), target: self, action: #selector(cancelRename(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancel, renameButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [grid, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = ScholiumGrid.Spacing.sectionSeparation
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let inset = ScholiumGrid.Spacing.sectionSeparation
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            view.widthAnchor.constraint(equalToConstant: 360),
        ])
        refreshSize()
    }

    func prepareForPresentation(in popover: NSPopover) {
        _ = view
        refreshSize()
        popover.contentViewController = self
        popover.contentSize = preferredContentSize
    }

    func focusName() {
        view.window?.makeKey()
        view.window?.makeFirstResponder(nameField)
        if let fieldEditor = nameField.currentEditor() as? NSTextView {
            fieldEditor.setSelectedRange(NSRange(location: 0, length: (nameField.stringValue as NSString).length))
        }
    }

    func updateAuthoritativeName(_ name: String) {
        currentName = name
        // Freeze the attempted name until rejection; never silently replace
        // the user's draft or authorize an edit across a concurrent rename.
    }

    @objc func submit(_ sender: Any?) {
        guard renameTask == nil else { return }
        let requested = nameField.stringValue
        guard requested != expectedName else {
            dismiss()
            return
        }
        let expected = expectedName
        nameField.isEditable = false
        renameButton.isEnabled = false
        renameTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.renameTask = nil
                self.nameField.isEditable = true
                self.renameButton.isEnabled = true
            }
            do {
                _ = try await self.rename(expected, requested)
                self.dismiss()
            } catch {
                self.expectedName = self.latestName() ?? self.currentName
                self.errorLabel.stringValue = error.localizedDescription
                self.errorLabel.isHidden = false
                self.nameField.setAccessibilityHelp(error.localizedDescription)
                self.refreshSize()
                if self.view.window != nil {
                    self.focusName()
                    NSAccessibility.post(element: self.errorLabel, notification: .valueChanged)
                }
            }
        }
    }

    @objc private func cancelRename(_ sender: Any?) { dismiss() }
    override func cancelOperation(_ sender: Any?) { dismiss() }

    private func refreshSize() {
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        view.setFrameSize(size)
        preferredContentSize = size
        onSizeChange?(size)
    }
}
