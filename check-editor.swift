// Exercises the real MarkdownTextView against the real edits.js: the text view
// wiring, undo, Enter/Tab handling, and image saving.
// Compiled together with the production source, so there is no second copy of
// the logic — only Renderer/FolderAccess are stubbed out.
// Usage: swiftc Sources/mdview/MarkdownEditor.swift check-editor.swift -o /tmp/ce && /tmp/ce
import AppKit
import SwiftUI

enum Renderer {
    static func resource(_ name: String, _ ext: String) -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Sources/mdview/Resources/\(name).\(ext)")
        return try! String(contentsOf: url, encoding: .utf8)
    }
}

enum FolderAccess {
    @discardableResult static func restore(_ folder: URL) -> Bool { true }
    static func grant(_ folder: URL) -> Bool { false }  // no panel in a test
}

@main
struct CheckEditor {
    static var failures = 0

    static func expect(_ label: String, _ got: String, _ want: String) {
        if got == want { print("ok: \(label)") }
        else { print("FAIL \(label)\n   got: \(got.debugDescription)\n  want: \(want.debugDescription)"); failures += 1 }
    }

    /// "a«bc»d" round-trips through the view's string + selectedRange.
    static func render(_ tv: NSTextView) -> String {
        let ns = NSMutableString(string: tv.string)
        let r = tv.selectedRange()
        ns.insert("»", at: r.location + r.length)
        ns.insert("«", at: r.location)
        return ns as String
    }

    static func view(_ marked: String) -> MarkdownTextView {
        let ns = NSMutableString(string: marked)
        let o = ns.range(of: "«"); ns.deleteCharacters(in: o)
        let c = ns.range(of: "»"); ns.deleteCharacters(in: c)
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tv.allowsUndo = true          // as makeNSView configures it
        tv.isRichText = false
        tv.string = ns as String
        tv.setSelectedRange(NSRange(location: o.location, length: c.location - o.location))
        return tv
    }

    static func main() {
        _ = NSApplication.shared

        // --- formatting reaches the text view and moves the selection ---
        let bold = view("say «hi» there")
        bold.applyEdit("bold")
        expect("bold applied to the text view", render(bold), "say **«hi»** there")

        let list = view("«one\ntwo»")
        list.applyEdit("bullet")
        expect("bullet applied across lines", render(list), "«- one\n- two»")

        let head = view("«title»")
        head.mdEdit(menuItem("heading2"))
        expect("heading level routed from the menu", render(head), "«## title»")

        // --- one undo step per command ---
        // undoManager comes from the window (the real app gets it from NSDocument),
        // so an offscreen window is needed for this to mean anything.
        let undo = view("«hi»")
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView?.addSubview(undo)
        win.makeFirstResponder(undo)
        assert(undo.undoManager != nil, "no undo manager — the check would be vacuous")
        undo.applyEdit("bold")
        expect("before undo", undo.string, "**hi**")
        undo.undoManager?.undo()
        expect("undo restores the original text", undo.string, "hi")

        // --- Enter and Tab, through the delegate the app installs ---
        let coord = MarkdownTextEditor(text: .constant(""), documentDirectory: nil)
            .makeCoordinator()

        let enter = view("- one«»")
        var handled = coord.textView(enter, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        expect("Enter continued the list", render(enter), "- one\n- «»")
        assert(handled, "Enter should have been handled inside a list")

        let plain = view("hello«»")
        handled = coord.textView(plain, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        expect("Enter left plain text alone", render(plain), "hello«»")
        assert(!handled, "Enter outside a list must fall through to a normal newline")

        let tab = view("- one«»")
        handled = coord.textView(tab, doCommandBy: #selector(NSResponder.insertTab(_:)))
        expect("Tab indented the list item", render(tab), "«  - one»")
        assert(handled, "Tab in a list should indent")

        let tabPlain = view("hello«»")
        handled = coord.textView(tabPlain, doCommandBy: #selector(NSResponder.insertTab(_:)))
        assert(!handled, "Tab outside a list must stay a plain tab")
        print("ok: Tab outside a list stays a plain tab")

        // --- pasted-URL detection ---
        assert(isLinkableURL("https://example.com"), "https should be linkable")
        assert(isLinkableURL("mailto:a@b.com"), "mailto should be linkable")
        assert(!isLinkableURL("just some text"), "prose must not become a link")
        assert(!isLinkableURL("https://a b"), "a URL with a space is not linkable")
        print("ok: only real URLs are turned into links on paste")

        // --- image saved beside the document ---
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mdedit-check-\(getpid())")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let when = Date(timeIntervalSince1970: 0)
        let stamped = DateFormatter()
        stamped.dateFormat = "yyyyMMdd-HHmmss"
        let name = "pasted-\(stamped.string(from: when)).png"

        let link = saveImageBesideDocument(Data("notreallyapng".utf8), ext: "PNG", in: dir, now: when)
        expect("image link is relative", link ?? "nil", "![](images/\(name))")
        assert(FileManager.default.fileExists(atPath: dir.appendingPathComponent("images/\(name)").path),
               "image file was not written")
        print("ok: image written into ./images next to the document")

        let denied = saveImageBesideDocument(Data(), ext: "png",
                                             in: URL(fileURLWithPath: "/no/such/place"), now: when)
        assert(denied == nil, "an unwritable folder must return nil, not a broken link")
        print("ok: unwritable folder returns nil rather than a dead link")

        print(failures == 0 ? "ALL EDITOR CHECKS PASSED" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }

    static func menuItem(_ kind: String) -> NSMenuItem {
        let i = NSMenuItem(); i.representedObject = kind; return i
    }
}
