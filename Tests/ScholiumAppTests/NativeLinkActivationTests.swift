import AppKit
import Testing

@testable import ScholiumEditor

@MainActor
@Suite("Native reading link activation", .serialized)
struct NativeLinkActivationTests {
    @Test("Only a completed single click without a selection follows its original link")
    func clickAdmission() {
        let origin = NSPoint(x: 10, y: 20)
        var click = NativeLinkClick(target: "note#heading", point: origin, clickCount: 1, modifiers: [])
        #expect(!click.admitsActivation(selection: [NSRange(location: 0, length: 0)], releaseTarget: "note#heading"))
        click.observe(type: .leftMouseUp, point: origin)
        #expect(click.admitsActivation(selection: [NSRange(location: 0, length: 0)], releaseTarget: "note#heading"))
        #expect(!click.admitsActivation(selection: [NSRange(location: 0, length: 3)], releaseTarget: "note#heading"))
        #expect(!click.admitsActivation(selection: [NSRange(location: 0, length: 0)], releaseTarget: "other"))
        click.observe(type: .leftMouseDragged, point: origin)
        #expect(!click.admitsActivation(selection: [NSRange(location: 0, length: 0)], releaseTarget: "note#heading"))
        for modifiers in [NSEvent.ModifierFlags.shift, .option, .control, .command] {
            var modified = NativeLinkClick(target: "note", point: origin, clickCount: 1, modifiers: modifiers)
            modified.observe(type: .leftMouseUp, point: origin)
            #expect(!modified.admitsActivation(selection: [], releaseTarget: "note"))
        }
        var double = NativeLinkClick(target: "note", point: origin, clickCount: 2, modifiers: [])
        double.observe(type: .leftMouseUp, point: origin)
        #expect(!double.admitsActivation(selection: [], releaseTarget: "note"))
    }

    @Test("System and keyboard link activation only enter the host callback")
    func hostOnlyActivation() throws {
        _ = NSApplication.shared
        let editor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        let source = "[site](https://example.invalid) and [[note]]"
        try editor.loadExactUTF8(Data(source.utf8))
        editor.viewMode = .reading
        let site = (editor.rawSource as NSString).range(of: "site").location
        let note = (editor.rawSource as NSString).range(of: "note").location
        #expect(editor.textStorage?.attribute(.link, at: site, effectiveRange: nil) == nil)
        #expect(!editor.isAutomaticLinkDetectionEnabled)
        var followed: [String] = []
        editor.onLinkActivation = { followed.append($0) }
        editor.clicked(onLink: "https://example.invalid", at: site)
        editor.clicked(onLink: "file:///private/secret", at: site)
        editor.clicked(onLink: "https://example.invalid", at: 0)
        editor.setSelectedRange(NSRange(location: note, length: 0))
        editor.openNativeLink(nil)
        #expect(followed == ["https://example.invalid", "note"])
        #expect(try editor.exactUTF8ForSaving() == Data(source.utf8))
    }
}
