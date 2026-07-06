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
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?
    @State private var editing = false

    var body: some View {
        Group {
            if editing {
                TextEditor(text: $document.text)
                    .font(.system(size: 13, design: .monospaced))
            } else {
                MarkdownWebView(markdown: document.text,
                                baseURL: fileURL?.deletingLastPathComponent())
            }
        }
        .frame(minWidth: 480, minHeight: 300)
        .toolbar {
            ToolbarItem {
                Button(editing ? "Preview" : "Edit",
                       systemImage: editing ? "eye" : "pencil") {
                    editing.toggle()
                }
                .keyboardShortcut("e", modifiers: .command)
                .help(editing ? "Show preview (⌘E)" : "Edit source (⌘E)")
            }
        }
    }
}

// MARK: - Renderer

enum Renderer {
    static func resource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
              let s = try? String(contentsOf: url, encoding: .utf8)
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
        </script></body></html>
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

struct MarkdownWebView: NSViewRepresentable {
    var markdown: String
    var baseURL: URL?

    final class Coordinator { var lastLoaded: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow file:// subresources (local relative images) from HTML loaded
        // with a file base URL. Private keys, fine for a local ad-hoc app.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // no white flash in dark mode
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoaded != markdown else { return }
        context.coordinator.lastLoaded = markdown
        webView.loadHTMLString(Renderer.html(for: markdown), baseURL: baseURL)
    }
}
