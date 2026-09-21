import SwiftUI
import AppKit
import JavaScriptCore
import UniformTypeIdentifiers

// MARK: - Bridge to the shared edits.js

// The editing operations live in JavaScript so the macOS app and the Tauri
// Windows shell run the same code. JavaScriptCore is a system framework, so
// this costs no dependency. JS strings and NSRange are both UTF-16, so
// offsets pass through untouched.
enum MarkdownEdits {
    private static let ctx: JSContext = {
        let c = JSContext()!
        c.exceptionHandler = { _, e in NSLog("edits.js: %@", e?.toString() ?? "unknown") }
        c.evaluateScript(Renderer.resource("edits", "js"))
        return c
    }()

    private static var api: JSValue? { ctx.objectForKeyedSubscript("MDEdits") }

    struct Result { let text: String; let range: NSRange }

    private static func unpack(_ v: JSValue?) -> Result? {
        guard let v, !v.isNull, !v.isUndefined else { return nil }
        let start = Int(v.objectForKeyedSubscript("start").toInt32())
        let end = Int(v.objectForKeyedSubscript("end").toInt32())
        return Result(text: v.objectForKeyedSubscript("text").toString(),
                      range: NSRange(location: start, length: max(0, end - start)))
    }

    static func apply(_ kind: String, text: String, range: NSRange, arg: Any? = nil) -> Result? {
        unpack(api?.objectForKeyedSubscript("apply")?
            .call(withArguments: [kind, text, range.location, range.location + range.length, arg as Any]))
    }

    /// Flip the Nth task marker. Shared with the preview's checkboxes.
    static func toggleTask(_ text: String, at index: Int) -> String {
        api?.objectForKeyedSubscript("toggleTask")?
            .call(withArguments: [text, index])?.toString() ?? text
    }

    static func continueList(text: String, at pos: Int) -> Result? {
        unpack(api?.objectForKeyedSubscript("continueList")?.call(withArguments: [text, pos]))
    }
}

/// A pasted string becomes a link only when it is unambiguously a URL.
func isLinkableURL(_ s: String) -> Bool {
    s.range(of: "^(https?://|mailto:)\\S+$", options: .regularExpression) != nil
}

/// Writes an image beside the document (into ./images) and returns the relative
/// markdown link, or nil if it could not be written.
func saveImageBesideDocument(_ data: Data, ext: String, in dir: URL,
                             now: Date = Date()) -> String? {
    let name = "pasted-\(imageStamp.string(from: now)).\(ext.isEmpty ? "png" : ext.lowercased())"
    let folder = dir.appendingPathComponent("images")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name))
    } catch { return nil }
    return "![](images/\(name))"
}

private let imageStamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f
}()

/// Routes a formatting command to whichever text view is focused, the same way
/// the Find commands reach the find bar.
func sendEditAction(_ kind: String) {
    let item = NSMenuItem()
    item.representedObject = kind
    NSApp.sendAction(#selector(MarkdownTextView.mdEdit(_:)), to: nil, from: item)
}

// MARK: - Text view

final class MarkdownTextView: NSTextView {
    /// Where pasted images get written; nil for an unsaved document.
    var documentDirectory: URL?

    func applyEdit(_ kind: String, arg: Any? = nil) {
        guard let r = MarkdownEdits.apply(kind, text: string, range: selectedRange(), arg: arg) else { return }
        replaceWholeText(with: r.text, selecting: r.range)
    }

    /// One undo step per command, and the binding updates via textDidChange.
    private func replaceWholeText(with text: String, selecting range: NSRange) {
        let whole = NSRange(location: 0, length: (string as NSString).length)
        insertText(text, replacementRange: whole)
        setSelectedRange(range)
    }

    @objc func mdEdit(_ sender: Any?) {
        guard let kind = (sender as? NSMenuItem)?.representedObject as? String else { return }
        // "heading1" … "heading6" carry their level in the name
        if kind.hasPrefix("heading"), let level = Int(kind.dropFirst("heading".count)) {
            applyEdit("heading", arg: level)
        } else {
            applyEdit(kind)
        }
    }

    // MARK: Paste

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let markdown = imageMarkdown(from: pb) {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        // a URL pasted over selected text becomes a link, as on GitHub
        if selectedRange().length > 0, let s = pb.string(forType: .string) {
            let url = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if isLinkableURL(url) {
                applyEdit("link", arg: url)
                return
            }
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? [])
            .filter(Self.isImage)
        if !dropped.isEmpty {
            let markdown = dropped.compactMap { url in
                (try? Data(contentsOf: url)).flatMap { save($0, ext: url.pathExtension) }
            }.joined(separator: "\n")
            if !markdown.isEmpty {
                insertText(markdown, replacementRange: selectedRange())
                return true
            }
        }
        return super.performDragOperation(sender)
    }

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    private func imageMarkdown(from pb: NSPasteboard) -> String? {
        if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: Self.isImage),
           let data = try? Data(contentsOf: url) {
            return save(data, ext: url.pathExtension)
        }
        if let png = pb.data(forType: .png) { return save(png, ext: "png") }
        if let tiff = pb.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return save(png, ext: "png")
        }
        return nil
    }

    /// Saves beside the document, asking for folder access once if the
    /// sandbox refuses the first attempt.
    private func save(_ data: Data, ext: String) -> String? {
        guard let dir = documentDirectory else { return nil }
        FolderAccess.restore(dir)
        if let link = saveImageBesideDocument(data, ext: ext, in: dir) { return link }
        guard FolderAccess.grant(dir), let link = saveImageBesideDocument(data, ext: ext, in: dir) else {
            NSSound.beep()
            return nil
        }
        return link
    }

}

// MARK: - SwiftUI wrapper

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var documentDirectory: URL?

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(_ text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }

        // Enter continues a list; Tab indents inside one. Anything we don't
        // claim falls through to the normal behaviour.
        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let tv = tv as? MarkdownTextView else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard let r = MarkdownEdits.continueList(text: tv.string, at: tv.selectedRange().location)
                else { return false }
                tv.insertText(r.text, replacementRange: NSRange(location: 0, length: (tv.string as NSString).length))
                tv.setSelectedRange(r.range)
                return true
            case #selector(NSResponder.insertTab(_:)):
                guard inList(tv) else { return false }
                tv.applyEdit("indent")
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                guard inList(tv) else { return false }
                tv.applyEdit("outdent")
                return true
            default:
                return false
            }
        }

        /// Tab only reformats when it would mean something: inside a list item,
        /// or across a multi-line selection. Otherwise it stays a plain tab.
        private func inList(_ tv: NSTextView) -> Bool {
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let line = ns.substring(with: ns.lineRange(for: NSRange(location: sel.location, length: 0)))
            if line.range(of: "^\\s*([-*+]|\\d+\\.)\\s", options: .regularExpression) != nil { return true }
            return ns.substring(with: sel).contains("\n")
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator($text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let tv = MarkdownTextView(frame: .zero)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        tv.delegate = context.coordinator
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        // Smart substitutions corrupt markdown source (curly quotes, em dashes)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.registerForDraggedTypes([.fileURL])
        tv.string = text

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? MarkdownTextView else { return }
        context.coordinator.text = $text
        tv.documentDirectory = documentDirectory
        // Only push external changes (e.g. document revert); typing already updated `text`
        if tv.string != text { tv.string = text }
    }
}

// MARK: - Format bar

struct FormatBar: View {
    private struct Item: Identifiable {
        let id = UUID()
        let kind: String, icon: String, name: String
    }

    private static let items: [Item] = [
        .init(kind: "bold", icon: "bold", name: "Bold (⌘B)"),
        .init(kind: "italic", icon: "italic", name: "Italic (⌘I)"),
        .init(kind: "strike", icon: "strikethrough", name: "Strikethrough (⇧⌘X)"),
        .init(kind: "code", icon: "chevron.left.forwardslash.chevron.right", name: "Inline code (⌃⌘C)"),
        .init(kind: "codeblock", icon: "curlybraces", name: "Code block"),
        .init(kind: "link", icon: "link", name: "Link (⌘K)"),
        .init(kind: "heading1", icon: "textformat.size.larger", name: "Heading 1 (⌘1)"),
        .init(kind: "heading2", icon: "textformat.size", name: "Heading 2 (⌘2)"),
        .init(kind: "heading3", icon: "textformat.size.smaller", name: "Heading 3 (⌘3)"),
        .init(kind: "quote", icon: "text.quote", name: "Quote (⇧⌘.)"),
        .init(kind: "bullet", icon: "list.bullet", name: "Bulleted list (⇧⌘8)"),
        .init(kind: "number", icon: "list.number", name: "Numbered list (⇧⌘7)"),
        .init(kind: "task", icon: "checklist", name: "Task list (⇧⌘L)"),
        .init(kind: "table", icon: "tablecells", name: "Table"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items) { item in
                Button { sendEditAction(item.kind) } label: {
                    Image(systemName: item.icon).frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .help(item.name)
                if item.kind == "link" || item.kind == "heading3" || item.kind == "task" {
                    Divider().frame(height: 14).padding(.horizontal, 4)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
