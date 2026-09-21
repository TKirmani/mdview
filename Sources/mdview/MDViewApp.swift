import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Document

extension UTType {
    static let md = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.md] }

    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ponytail: viewer-style utility — quit when the last document closes.
    // DocumentGroup prompts for unsaved changes before the window closes, so no data loss.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MDViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: NSScreen.main?.visibleFrame.width ?? 1440,
                     height: NSScreen.main?.visibleFrame.height ?? 900)
        .commands {
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Find…") { sendFindAction(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find and Replace…") { sendFindAction(.showReplaceInterface) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { sendFindAction(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { sendFindAction(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandMenu("Format") {
                Button("Bold") { sendEditAction("bold") }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { sendEditAction("italic") }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Strikethrough") { sendEditAction("strike") }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                // ⌘E would be GitHub's binding, but macOS reserves it for
                // Use Selection for Find.
                Button("Inline Code") { sendEditAction("code") }
                    .keyboardShortcut("c", modifiers: [.command, .control])
                Button("Code Block") { sendEditAction("codeblock") }
                Button("Link") { sendEditAction("link") }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Heading 1") { sendEditAction("heading1") }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Heading 2") { sendEditAction("heading2") }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Heading 3") { sendEditAction("heading3") }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Quote") { sendEditAction("quote") }
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Bulleted List") { sendEditAction("bullet") }
                    .keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { sendEditAction("number") }
                    .keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Task List") { sendEditAction("task") }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Table") { sendEditAction("table") }
            }
        }
    }
}

// SwiftUI's default menu bar has no Find menu, so ⌘F/⌘⌥F need an explicit
// command sending the same message the inline find bar (usesFindBar) listens for.
private func sendFindAction(_ action: NSTextFinder.Action) {
    let item = NSMenuItem()
    item.tag = action.rawValue
    NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?
    @State private var editing = false

    var body: some View {
        Group {
            if editing {
                VStack(spacing: 0) {
                    FormatBar()
                    Divider()
                    MarkdownTextEditor(text: $document.text,
                                       documentDirectory: fileURL?.deletingLastPathComponent())
                }
            } else {
                MarkdownWebView(markdown: document.text,
                                baseURL: fileURL?.deletingLastPathComponent(),
                                applyText: { document.text = $0 })
            }
        }
        .frame(minWidth: 480, minHeight: 300)
        .toolbar {
            ToolbarItem {
                Button(editing ? "Preview" : "Edit",
                       systemImage: editing ? "eye" : "pencil") {
                    editing.toggle()
                }
                // ⇧⌘E, not ⌘E — the system Find menu owns ⌘E (Use Selection for Find)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help(editing ? "Show preview (⇧⌘E)" : "Edit source (⇧⌘E)")
            }
        }
    }
}

// MARK: - Renderer

enum Renderer {
    static func resource(_ name: String, _ ext: String) -> String {
        // Bundle.main is the packaged .app (build.sh copies these into
        // Contents/Resources); Bundle.module covers `swift run`. Do NOT rely on
        // Bundle.module alone — SwiftPM's accessor falls back to a hardcoded
        // .build path that only exists on the machine that compiled it.
        let url = Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
        guard let url, let s = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("missing bundled resource \(name).\(ext)") }
        return s
    }

    static let template: String = {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>\(resource("style", "css"))</style>
        <style media="not (prefers-color-scheme: dark)">\(resource("hljs-github", "css"))</style>
        <style media="(prefers-color-scheme: dark)">\(resource("hljs-github-dark", "css"))</style>
        <script>\(resource("marked.min", "js"))</script>
        <script>\(resource("marked-footnote.min", "js"))</script>
        <script>\(resource("highlight.min", "js"))</script>
        </head><body><article id="c"></article>
        <script>
        marked.use({ gfm: true }, markedFootnote());
        document.getElementById("c").innerHTML = marked.parse(__MD__);
        document.querySelectorAll("pre code").forEach(el => hljs.highlightElement(el));
        </script>
        <script>\(resource("interactive", "js"))</script></body></html>
        """
    }()

    static func html(for markdown: String) -> String {
        // JSON-encode the markdown as a JS string literal; escape "</" so
        // embedded "</script>" in the document can't break out of the tag.
        let data = try! JSONSerialization.data(withJSONObject: markdown, options: .fragmentsAllowed)
        let js = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: "__MD__", with: js)
    }
}

// Serves the document's own directory over a custom scheme so relative images
// load without the private file-access preference keys App Store review flags.
// Confined to `root` — nothing above it is readable.
let mdResourceScheme = "mdres"

// Under the App Sandbox the app may read the opened .md file but not its
// siblings, so local images fail. The user can grant the containing folder
// once; the security-scoped bookmark makes it stick across launches.
// Unsandboxed builds never hit this — reads just succeed.
enum FolderAccess {
    private static let key = "grantedFolderBookmarks"  // [folder path: bookmark]
    private static var active: [String: URL] = [:]     // held open for the process lifetime

    private static var stored: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Reopens a previously granted folder (or any granted ancestor of it).
    @discardableResult
    static func restore(_ folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        if active.keys.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        guard let granted = stored.first(where: { path == $0.key || path.hasPrefix($0.key + "/") })
        else { return false }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: granted.value, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return false }
        active[granted.key] = url
        return true
    }

    /// Asks for the folder, then remembers it. Returns true if access was gained.
    static func grant(_ folder: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = "Allow MDView to show images stored in this folder."
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return false }

        let path = url.standardizedFileURL.path
        stored[path] = data
        _ = url.startAccessingSecurityScopedResource()
        active[path] = url
        return true
    }
}

final class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    var root: URL?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let root = root?.standardizedFileURL,
              let url = task.request.url,
              let rel = url.path.removingPercentEncoding?.drop(while: { $0 == "/" }),
              !rel.isEmpty
        else { return task.didFailWithError(URLError(.badURL)) }

        let file = root.appendingPathComponent(String(rel)).standardizedFileURL
        // "../" escapes stay inside the document's folder
        guard file.path.hasPrefix(root.path + "/") else {
            return task.didFailWithError(URLError(.noPermissionsToReadFile))
        }
        // Sandboxed: a previously granted folder has to be reopened each launch.
        FolderAccess.restore(root)
        guard let data = try? Data(contentsOf: file)
        else { return task.didFailWithError(URLError(.noPermissionsToReadFile)) }

        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime,
                                    expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct MarkdownWebView: NSViewRepresentable {
    var markdown: String
    var baseURL: URL?
    var applyText: (String) -> Void  // write an edited source back to the document

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var lastLoaded: String?
        var markdown = ""
        var applyText: (String) -> Void = { _ in }
        var reload: (() -> Void)?
        let resources = DocumentResourceHandler()

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            switch kind {
            case "toggle":
                guard let i = body["index"] as? Int else { return }
                let updated = MarkdownEdits.toggleTask(markdown, at: i)
                guard updated != markdown else { return }
                // The DOM checkbox already flipped visually; suppress the reload
                // this edit would otherwise trigger so scroll position is kept.
                lastLoaded = updated
                markdown = updated
                applyText(updated)
            case "copy":
                if let text = body["text"] as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            case "grantAccess":
                // Only reached when an image failed to load, i.e. sandboxed builds.
                guard let root = resources.root, FolderAccess.grant(root) else { return }
                lastLoaded = nil                     // force a fresh render
                reload?()
            default: break
            }
        }

        // Open real links in the default browser instead of replacing the preview.
        // In-page "#anchor" jumps and the initial load stay in the web view.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url,
               let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator.resources, forURLScheme: mdResourceScheme)
        // ponytail: retains the coordinator for the web view's lifetime — fine
        // for a per-window viewer; add removeScriptMessageHandler only if reused.
        config.userContentController.add(context.coordinator, name: "bridge")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // no white flash in dark mode
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.markdown = markdown
        context.coordinator.applyText = applyText
        context.coordinator.resources.root = baseURL
        context.coordinator.reload = { [weak webView] in
            guard let webView else { return }
            webView.loadHTMLString(Renderer.html(for: markdown),
                                   baseURL: URL(string: "\(mdResourceScheme):///"))
        }
        guard context.coordinator.lastLoaded != markdown else { return }
        context.coordinator.lastLoaded = markdown
        // Base the page on the custom scheme, so relative image paths resolve to
        // it with no rewriting and "#anchor" links stay same-document.
        webView.loadHTMLString(Renderer.html(for: markdown),
                               baseURL: URL(string: "\(mdResourceScheme):///"))
    }
}
