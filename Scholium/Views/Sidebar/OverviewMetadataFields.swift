import AppKit
import ScholiumContracts
import SwiftUI

enum OverviewFieldLayout {
    static let fontSize: CGFloat = NSFont.systemFontSize
    static let minimumLabelWidth: CGFloat = 44
    static let columnSpacing: CGFloat = 8
    static let rowHeight: CGFloat = 28

    static func labelWidth(in width: CGFloat, labels: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let natural = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(min(max(minimumLabelWidth, natural), max(minimumLabelWidth, width * 0.3)))
    }
}

/// A stable native field collection. AppKit's key loop handles Tab immediately;
/// no declarative render or asynchronous save stands between input events.
struct OverviewMetadataFields: NSViewRepresentable {
    let note: WindowDocumentLocation
    let catalog: NoteMetadataCatalog
    let visibleKeys: [String]
    let context: ResearchInspectorContentContext
    @Binding var measuredHeight: CGFloat
    @Binding var measuredLabelWidth: CGFloat

    func makeNSView(context: Context) -> MetadataFieldsHost {
        let host = MetadataFieldsHost()
        configure(host)
        return host
    }

    func updateNSView(_ host: MetadataFieldsHost, context: Context) {
        configure(host)
        if !context.environment.isEnabled { host.finishInput() }
    }

    private func configure(_ host: MetadataFieldsHost) {
        host.heightChanged = { height in
            DispatchQueue.main.async { if abs(measuredHeight - height) > 0.5 { measuredHeight = height } }
        }
        host.labelWidthChanged = { width in
            DispatchQueue.main.async { if abs(measuredLabelWidth - width) > 0.5 { measuredLabelWidth = width } }
        }
        host.session.save = { fields, revision in try await context.saveMetadata(note, fields, revision) }
        host.session.reload = { try await context.reloadMetadata(note) }
        host.session.configure(note: note, catalog: catalog, visible: visibleKeys)
        context.registerMetadataFlush(host.token, host.flush)
        host.unregister = context.unregisterMetadataFlush
        host.refresh()
    }

    static func dismantleNSView(_ host: MetadataFieldsHost, coordinator: ()) {
        host.unregister?(host.token)
    }
}

@MainActor final class MetadataFieldsHost: NSView, NSUserInterfaceValidations {
    let session = OverviewMetadataSession()
    let token = UUID()
    var unregister: ((UUID) -> Void)?
    var heightChanged: ((CGFloat) -> Void)?
    var labelWidthChanged: ((CGFloat) -> Void)?
    private let grid = NSGridView(numberOfColumns: 2, rows: 0)
    private var rowTitles: [String: NSTextField] = [:]
    private var rows: [String: NSStackView] = [:]
    private var fields: [String: MetadataTextField] = [:]
    private var actions: [String: MetadataActionButton] = [:]
    private var choices: [String: MetadataChoiceButton] = [:]
    private var toggles: [String: MetadataToggleButton] = [:]
    private var labels: [String: NSTextField] = [:]
    private var expandedNames: Set<UUID> = []
    private var previousError: String?
    private var keyViews: [NSView] = []

    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { session.undoManager }

    override init(frame: NSRect) {
        super.init(frame: frame)
        grid.columnSpacing = OverviewFieldLayout.columnSpacing
        grid.rowSpacing = 6
        grid.rowAlignment = .firstBaseline
        grid.yPlacement = .top
        grid.column(at: 0).width = OverviewFieldLayout.minimumLabelWidth
        grid.column(at: 0).xPlacement = .fill
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityIdentifier("scholium.overview.fields")
        session.changed = { [weak self] in self?.refresh() }
        session.didCommit = { [weak self] in
            guard let self else { return }
            for field in self.fields.values where !self.session.dirtyKeys.contains(field.key) { field.clearDraftUndo() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        let width = OverviewFieldLayout.labelWidth(in: bounds.width, labels: rowTitles.values.map(\.stringValue))
        if abs(grid.column(at: 0).width - width) > 0.5 {
            grid.column(at: 0).width = width
            labelWidthChanged?(width)
        }
        super.layout()
        grid.layoutSubtreeIfNeeded()
        heightChanged?(grid.fittingSize.height)
    }

    func flush() async throws {
        guard session.composing.isEmpty else {
            try await session.flush()
            return
        }
        window?.makeFirstResponder(self)
        try await session.flush()
    }

    func finishInput() {
        if let editor = window?.firstResponder as? NSTextView,
            fields.values.contains(where: { $0.currentEditor() === editor })
        {
            window?.makeFirstResponder(self)
        }
        session.requestCommit()
    }

    @objc func undo(_ sender: Any?) { Task { try? await session.undoCommitted() } }
    @objc func redo(_ sender: Any?) { Task { try? await session.redoCommitted() } }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return session.undoManager.canUndo || !session.dirtyKeys.isEmpty || session.isSaving }
        if item.action == #selector(redo(_:)) { return session.undoManager.canRedo }
        return true
    }

    func refresh() {
        var wanted: [NSView] = []
        var fieldIDs = Set<String>()
        keyViews = []
        for key in session.orderedVisibleKeys {
            guard let field = session.fields.first(where: { $0.key == key }), let draft = session.drafts[key] else { continue }
            if field.valueKind == .creatorList && !field.isReadOnly {
                for (index, creator) in draft.creators.enumerated() {
                    let prefix = key + "." + creator.id.uuidString
                    var content: [NSView] = []
                    let names = creator.singleName ? ["literal"] : ["family", "given"]
                    for name in names {
                        let title =
                            name == "literal"
                            ? String(localized: "Single Name") : name == "family" ? String(localized: "Family Name") : String(localized: "Given Name")
                        content.append(
                            input(
                                prefix + "." + name, key: key,
                                label: "\(field.label), \(index + 1), \(title)",
                                placeholder: name == "family" ? String(localized: "Last name") : name == "given" ? String(localized: "First name") : title,
                                value: creator.values[name] ?? "", multiline: false,
                                changed: { [weak self] value in
                                    self?.session.edit(key) { draft in
                                        guard let index = draft.creators.firstIndex(where: { $0.id == creator.id }) else { return }
                                        draft.creators[index].values[name] = value
                                    }
                                }))
                        fieldIDs.insert(prefix + "." + name)
                    }
                    content.append(
                        action(prefix + ".more", symbol: "ellipsis", title: String(localized: "Creator Options") + ", \(index + 1)") { [weak self] in
                            self?.showCreatorMenu(key: key, creator: creator, index: index, anchor: prefix + ".more")
                        })
                    let creatorRow = row(prefix, label: index == 0 ? rowLabel(field) : "", content: content)
                    let inputs = content.compactMap { $0 as? MetadataTextField }
                    if inputs.count == 2,
                        !creatorRow.constraints.contains(where: {
                            $0.firstItem === inputs[0] && $0.secondItem === inputs[1] && $0.firstAttribute == .width
                        })
                    {
                        inputs[0].widthAnchor.constraint(equalTo: inputs[1].widthAnchor).isActive = true
                    }
                    wanted.append(creatorRow)
                    if expandedNames.contains(creator.id), !creator.singleName {
                        for (name, title) in [
                            ("suffix", String(localized: "Suffix")), ("non_dropping_particle", String(localized: "Non-dropping Particle")),
                            ("dropping_particle", String(localized: "Dropping Particle")),
                        ] {
                            let id = prefix + "." + name
                            let control = input(
                                id, key: key, label: "\(field.label), \(index + 1), \(title)", placeholder: "", value: creator.values[name] ?? "",
                                multiline: false
                            ) { [weak self] value in
                                self?.session.edit(key) { draft in
                                    guard let index = draft.creators.firstIndex(where: { $0.id == creator.id }) else { return }
                                    draft.creators[index].values[name] = value
                                }
                            }
                            fieldIDs.insert(id)
                            wanted.append(row(id, label: title, content: [control]))
                        }
                    }
                }
                let add = action(
                    key + ".add", symbol: "plus", title: key == "authors" ? String(localized: "Add Author") : String(localized: "Add Creator"), showsTitle: true
                ) { [weak self] in
                    self?.addCreator(key: key)
                }
                wanted.append(row(key + ".add", label: "", content: [add]))
            } else if (field.valueKind == .textList || field.valueKind == .tags) && !field.isReadOnly {
                for (index, item) in draft.list.enumerated() {
                    let id = key + "." + item.id.uuidString
                    let control = input(id, key: key, label: "\(field.label), \(index + 1)", placeholder: field.label, value: item.text, multiline: true) {
                        [weak self] value in
                        self?.session.edit(key) { draft in
                            guard let index = draft.list.firstIndex(where: { $0.id == item.id }) else { return }
                            draft.list[index].text = value
                        }
                    }
                    fieldIDs.insert(id)
                    let remove = { [weak self] in
                        guard let self else { return }
                        self.finishInput()
                        self.session.edit(key) { draft in
                            draft.list.removeAll { $0.id == item.id }
                            if draft.list.isEmpty { draft.list = [OverviewMetadataListValue(text: "")] }
                        }
                        self.refresh()
                        self.session.requestCommit()
                    }
                    let add = { [weak self] in
                        guard let self else { return }
                        let item = OverviewMetadataListValue(text: "")
                        self.session.edit(key) { $0.list.insert(item, at: min(index + 1, $0.list.count)) }
                        self.refresh()
                        self.focus(key + "." + item.id.uuidString)
                    }
                    let options = action(id + ".more", symbol: "ellipsis", title: field.label + ", \(index + 1)") { [weak self] in
                        guard let self, let button = self.actions[id + ".more"] else { return }
                        let menu = NSMenu()
                        menu.addItem(self.menuItem(String(localized: "Add Value"), action: add))
                        menu.addItem(self.menuItem(String(localized: "Remove value \(index + 1)"), action: remove))
                        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
                    }
                    wanted.append(row(id, label: index == 0 ? rowLabel(field) : "", content: [control, options]))
                }
            } else if field.controlStyle == .toggle && !field.isReadOnly {
                let control = toggles[key] ?? MetadataToggleButton()
                toggles[key] = control
                control.state = draft.boolean ? .on : .off
                control.setAccessibilityLabel(field.label)
                control.setAccessibilityIdentifier("scholium.overview.input.\(key)")
                control.choose = { [weak self, weak control] in
                    guard let self, let control else { return }
                    self.session.edit(key) { $0.boolean = control.state == .on }
                    self.session.requestCommit()
                }
                keyViews.append(control)
                wanted.append(row(key, label: rowLabel(field), content: [control]))
            } else if field.controlStyle == .choicePicker && !field.isReadOnly {
                let control = choices[key] ?? MetadataChoiceButton()
                choices[key] = control
                let titles =
                    [String(localized: "Not specified")]
                    + (field.allowedValues ?? []).map {
                        PropertyPresentationCatalog.choiceDisplayName(for: $0, fieldKey: key)
                    }
                if control.itemTitles != titles {
                    control.removeAllItems()
                    control.addItems(withTitles: titles)
                }
                let index = field.allowedValues?.firstIndex(of: draft.text).map { $0 + 1 } ?? 0
                control.selectItem(at: index)
                control.setAccessibilityLabel(field.label)
                control.setAccessibilityIdentifier("scholium.overview.input.\(key)")
                control.choose = { [weak self, weak control] in
                    guard let self, let control else { return }
                    self.session.edit(key) { draft in
                        draft.text = control.indexOfSelectedItem > 0 ? field.allowedValues?[control.indexOfSelectedItem - 1] ?? "" : ""
                    }
                    self.session.requestCommit()
                }
                keyViews.append(control)
                wanted.append(row(key, label: rowLabel(field), content: [control]))
            } else {
                let control = input(
                    key, key: key, label: field.label, placeholder: placeholder(for: field),
                    value: field.isReadOnly ? (draft.original?.scalarString ?? String(localized: "Unsupported value")) : draft.text,
                    multiline: field.controlStyle == .multilineText || field.valueKind == .text
                ) { [weak self] value in
                    self?.session.edit(key) { $0.text = value }
                }
                control.isEditable = !field.isReadOnly
                fieldIDs.insert(key)
                wanted.append(row(key, label: rowLabel(field), content: [control]))
            }
            if let error = session.error, error.key == key {
                let id = key + ".error"
                let label = labels[id] ?? NSTextField(wrappingLabelWithString: "")
                labels[id] = label
                label.stringValue = error.message
                label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                label.textColor = .systemRed
                label.setAccessibilityLabel(error.message)
                wanted.append(
                    row(
                        id, label: "",
                        content: [
                            label,
                            action(id + ".recover", symbol: "ellipsis", title: String(localized: "Resolve Metadata Error")) { [weak self] in
                                self?.showRecoveryMenu(key, anchor: id + ".recover")
                            },
                        ]))
                for field in fields.values where field.key == key { field.setAccessibilityHelp(error.message) }
            }
        }
        for (id, field) in fields where !fieldIDs.contains(id) {
            field.delegate = nil
            fields.removeValue(forKey: id)
        }
        // Reconcile rows by their retained native content. Ordinary typing never
        // removes/recreates a field, its editor, or the grid's shared columns.
        for index in (0..<grid.numberOfRows).reversed() {
            if let view = grid.cell(atColumnIndex: 1, rowIndex: index).contentView,
                !wanted.contains(view)
            {
                let title = grid.cell(atColumnIndex: 0, rowIndex: index).contentView
                grid.removeRow(at: index)
                title?.removeFromSuperview()
                view.removeFromSuperview()
            }
        }
        for (index, view) in wanted.enumerated() {
            if let cell = grid.cell(for: view), let row = cell.row {
                let current = grid.index(of: row)
                if current != index { grid.moveRow(at: current, to: index) }
            } else if let id = rows.first(where: { $0.value === view })?.key,
                let title = rowTitles[id]
            {
                grid.insertRow(at: index, with: [title, view])
            }
        }
        rows = rows.filter { wanted.contains($0.value) }
        actions = actions.filter { $0.value.isDescendant(of: self) }
        choices = choices.filter { $0.value.isDescendant(of: self) }
        toggles = toggles.filter { $0.value.isDescendant(of: self) }
        labels = labels.filter { $0.value.isDescendant(of: self) }
        rowTitles = rowTitles.filter { rows[$0.key] != nil }
        window?.recalculateKeyViewLoop()
        keyViews = keyViews.filter { $0.isDescendant(of: self) }
        // Native controls, including every collection action, form one loop.
        for index in 0..<max(0, keyViews.count - 1) { keyViews[index].nextKeyView = keyViews[index + 1] }
        invalidateIntrinsicContentSize()
        needsLayout = true
        if session.error?.message != previousError {
            previousError = session.error?.message
            if let message = previousError {
                NSAccessibility.post(
                    element: self, notification: .announcementRequested,
                    userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        }
    }

    private func rowLabel(_ field: PropertyEditorField) -> String {
        switch field.key {
        case "type": String(localized: "Item Type")
        case "authors": String(localized: "Author")
        case "publication_date": String(localized: "Date")
        case "container_title": String(localized: "Publication")
        case "publisher_place": String(localized: "Place")
        default: field.label
        }
    }

    private func row(_ id: String, label: String, content: [NSView]) -> NSStackView {
        if let existing = rows[id] {
            rowTitles[id]?.stringValue = label
            reconcile(existing, content)
            return existing
        }
        let title = NSTextField(wrappingLabelWithString: label)
        title.alignment = .right
        title.font = .systemFont(ofSize: OverviewFieldLayout.fontSize)
        title.textColor = ScholiumNativeColorRole.secondaryLabel.nsColor
        title.toolTip = label
        title.setAccessibilityElement(false)
        title.translatesAutoresizingMaskIntoConstraints = false
        rowTitles[id] = title
        let row = NSStackView(views: content)
        row.orientation = .horizontal
        row.alignment = content.contains { ($0 as? MetadataTextField)?.multiline == true } ? .top : .centerY
        row.spacing = OverviewFieldLayout.columnSpacing
        if content.contains(where: { $0 is MetadataTextField || $0 is MetadataChoiceButton }) {
            row.distribution = .fill
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: OverviewFieldLayout.rowHeight).isActive = true
        rows[id] = row
        return row
    }

    private func reconcile(_ stack: NSStackView, _ views: [NSView]) {
        guard stack.arrangedSubviews != views else { return }
        for old in stack.arrangedSubviews where !views.contains(old) {
            stack.removeArrangedSubview(old)
            old.removeFromSuperview()
        }
        for (index, view) in views.enumerated() {
            if stack.arrangedSubviews.indices.contains(index), stack.arrangedSubviews[index] === view { continue }
            if stack.arrangedSubviews.contains(view) { stack.removeArrangedSubview(view) }
            stack.insertArrangedSubview(view, at: index)
        }
    }

    private func input(
        _ id: String, key: String, label: String, placeholder: String, value: String,
        multiline: Bool, changed: @escaping (String) -> Void
    ) -> MetadataTextField {
        let field = fields[id] ?? MetadataTextField()
        fields[id] = field
        field.key = key
        field.identity = id
        field.representedValue = value
        field.host = self
        field.changed = changed
        field.placeholderString = placeholder
        field.toolTip = value.isEmpty ? label : value
        field.setAccessibilityLabel(label)
        field.setAccessibilityIdentifier("scholium.overview.input.\(id)")
        field.setAccessibilityHelp(session.error?.key == key ? session.error?.message : nil)
        field.multiline = multiline
        field.allowsLineBreaks = session.fields.first(where: { $0.key == key })?.controlStyle == .multilineText
        if field.currentEditor() == nil, field.stringValue != value { field.stringValue = value }
        keyViews.append(field)
        return field
    }

    private func action(_ id: String, symbol: String, title: String, showsTitle: Bool = false, perform: @escaping () -> Void) -> MetadataActionButton {
        let button = actions[id] ?? MetadataActionButton(title: showsTitle ? title : nil)
        actions[id] = button
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier("scholium.overview.action.\(id)")
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.perform = perform
        keyViews.append(button)
        return button
    }

    private func menuItem(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = MetadataMenuItem(title: title, action: #selector(MetadataMenuItem.invoke), keyEquivalent: "")
        item.target = item
        item.perform = action
        item.isEnabled = enabled
        return item
    }

    private func showRecoveryMenu(_ key: String, anchor: String) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if session.error != nil {
            menu.addItem(menuItem(String(localized: "Retry")) { [weak self] in self?.session.requestCommit() })
            menu.addItem(menuItem(String(localized: "Reload Metadata")) { [weak self] in self?.session.reloadCurrent() })
        }
        if let button = actions[anchor] { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button) }
    }

    private func placeholder(for field: PropertyEditorField) -> String {
        guard !field.isReadOnly else { return "" }
        if field.controlStyle == .dateField { return String(localized: "Year or date") }
        return field.label
    }

    private func addCreator(key: String) {
        let creator = OverviewMetadataCreator()
        session.edit(key) { $0.creators.append(creator) }
        refresh()
        focus(key + "." + creator.id.uuidString + ".family")
    }

    private func showCreatorMenu(key: String, creator: OverviewMetadataCreator, index: Int, anchor: String) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(
            menuItem(String(localized: "Remove creator \(index + 1)")) { [weak self] in
                guard let self else { return }
                self.finishInput()
                self.session.edit(key) { draft in
                    draft.creators.removeAll { $0.id == creator.id }
                    if draft.creators.isEmpty { draft.creators = [OverviewMetadataCreator()] }
                }
                self.refresh()
                self.session.requestCommit()
            })
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            menuItem(creator.singleName ? String(localized: "Use Family and Given Names") : String(localized: "Use Single Name")) { [weak self] in
                guard let self else { return }
                self.finishInput()
                self.session.edit(key) { draft in
                    guard let index = draft.creators.firstIndex(where: { $0.id == creator.id }) else { return }
                    if creator.singleName {
                        draft.creators[index].values = ["family": creator.values["literal"] ?? ""]
                    } else {
                        let name = [creator.values["family"], creator.values["given"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                        draft.creators[index].values = ["literal": name]
                    }
                    draft.creators[index].singleName.toggle()
                }
                self.refresh()
                self.session.requestCommit()
            })
        if !creator.singleName {
            menu.addItem(
                menuItem(String(localized: "Additional Name Fields")) { [weak self] in
                    guard let self else { return }
                    if self.expandedNames.contains(creator.id) { self.expandedNames.remove(creator.id) } else { self.expandedNames.insert(creator.id) }
                    self.refresh()
                })
        }
        for (offset, title) in [(-1, String(localized: "Move Up")), (1, String(localized: "Move Down"))] {
            let count = session.drafts[key]?.creators.count ?? 0
            menu.addItem(
                menuItem(title, enabled: (0..<count).contains(index + offset)) { [weak self] in
                    guard let self else { return }
                    self.finishInput()
                    self.session.edit(key) { $0.creators.swapAt(index, index + offset) }
                    self.refresh()
                    self.session.requestCommit()
                })
        }
        if let button = actions[anchor] { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button) }
    }

    func focusFirstInput(for key: String) {
        guard let field = keyViews.compactMap({ $0 as? MetadataTextField }).first(where: { $0.key == key }) else { return }
        window?.makeFirstResponder(field)
    }

    private func focus(_ id: String) {
        layoutSubtreeIfNeeded()
        if let field = fields[id] {
            window?.makeFirstResponder(field)
            field.scrollToVisible(field.bounds)
        }
    }
}

@MainActor private final class MetadataMenuItem: NSMenuItem {
    var perform: (() -> Void)?
    @objc func invoke() { perform?() }
}

@MainActor final class MetadataActionButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    var perform: (() -> Void)?
    init(title: String? = nil) {
        super.init(frame: .zero)
        self.title = title ?? ""
        font = .systemFont(ofSize: NSFont.systemFontSize)
        isBordered = false
        imagePosition = title == nil ? .imageOnly : .imageLeading
        bezelStyle = .accessoryBarAction
        target = self
        action = #selector(invoke)
        translatesAutoresizingMaskIntoConstraints = false
        if title == nil { widthAnchor.constraint(equalToConstant: 28).isActive = true }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { perform?() }
}

@MainActor final class MetadataChoiceButton: NSPopUpButton {
    var choose: (() -> Void)?
    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = true
        font = .systemFont(ofSize: NSFont.systemFontSize)
        target = self
        action = #selector(invoke)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { choose?() }
}

/// A native checkbox keeps Boolean fields distinct from text and enumerations.
@MainActor final class MetadataToggleButton: NSButton {
    var choose: (() -> Void)?
    init() {
        super.init(frame: .zero)
        setButtonType(.switch)
        title = ""
        target = self
        action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { choose?() }
}
