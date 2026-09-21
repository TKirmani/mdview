// Verifies relative images load through the mdres:// scheme handler (no private
// allowFileAccessFromFileURLs KVC), and that path traversal is refused.
// Usage: swift check-resources.swift
import AppKit
import WebKit
import UniformTypeIdentifiers

// --- the code under test, kept identical to MDViewApp.swift ---
let mdResourceScheme = "mdres"

final class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
    var root: URL?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let root = root?.standardizedFileURL,
              let url = task.request.url,
              let rel = url.path.removingPercentEncoding?.drop(while: { $0 == "/" }),
              !rel.isEmpty
        else { return task.didFailWithError(URLError(.badURL)) }

        let file = root.appendingPathComponent(String(rel)).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file)
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
// --- end code under test ---

// A document dir holding one 2x2 red PNG, plus a secret one level up.
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mdres-check-\(getpid())")
let docDir = tmp.appendingPathComponent("doc")
try! FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

// built pixel-exact: NSImage.lockFocus would render at the display backing scale
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 8, bitsPerPixel: 32)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: docDir.appendingPathComponent("pic.png"))
try! Data("TOPSECRET".utf8).write(to: tmp.appendingPathComponent("secret.txt"))

let handler = DocumentResourceHandler()
handler.root = docDir

let config = WKWebViewConfiguration()
config.setURLSchemeHandler(handler, forURLScheme: mdResourceScheme)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), configuration: config)

final class Nav: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done = true }
}
let nav = Nav()
web.navigationDelegate = nav

// Mirrors what MarkdownWebView does: HTML string based on the custom scheme.
let interactiveJS = try! String(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/mdview/Resources/interactive.js"), encoding: .utf8)

let html = """
<!doctype html><html><body>
<img id="ok" src="pic.png">
<img id="escaped" src="../secret.txt">
<a id="anchor" href="#deep">jump</a><div id="deep" style="margin-top:2000px">x</div>
<script>\(interactiveJS)</script>
</body></html>
"""
web.loadHTMLString(html, baseURL: URL(string: "\(mdResourceScheme):///"))

func pump(until cond: () -> Bool, timeout: TimeInterval, _ label: String) {
    let deadline = Date().addingTimeInterval(timeout)
    while !cond() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    assert(cond(), "timed out waiting for: \(label)")
}

func eval(_ s: String) -> Any? {
    var out: Any?
    var finished = false
    web.evaluateJavaScript(s) { v, err in
        if let err = err { fatalError("JS error in \(s.prefix(40)): \(err)") }
        out = v; finished = true
    }
    pump(until: { finished }, timeout: 5, "js eval")
    return out
}

pump(until: { nav.done }, timeout: 5, "page load")

// relative src must resolve onto the custom scheme, not about:blank
let resolved = eval("document.getElementById('ok').src") as? String ?? ""
assert(resolved == "mdres:///pic.png", "relative src resolved to \(resolved)")
print("ok: relative src resolves to \(resolved)")

// and it must actually decode -> the handler served real bytes
pump(until: { (eval("document.getElementById('ok').naturalWidth") as? Int ?? 0) > 0 },
     timeout: 5, "image decode")
assert(eval("document.getElementById('ok').naturalWidth") as? Int == 2, "wrong image size")
print("ok: image loaded through mdres:// (naturalWidth == 2)")

// "../" must not escape the document directory
assert(eval("document.getElementById('escaped').naturalWidth") as? Int == 0,
       "path traversal was served!")
print("ok: ../secret.txt refused (traversal blocked)")

// anchors stay same-document rather than triggering a navigation
nav.done = false
_ = eval("document.getElementById('anchor').click()")
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
assert(!nav.done, "anchor click caused a page navigation")
assert((eval("window.location.hash") as? String) == "#deep", "anchor did not apply")
print("ok: #anchor stays same-document (no reload)")

// The app derives root as fileURL.deletingLastPathComponent(), which yields a
// trailing slash — resolution must not differ from the plain directory URL.
handler.root = docDir.appendingPathComponent("note.md").deletingLastPathComponent()
nav.done = false
web.loadHTMLString("<img id='ok' src='pic.png'>", baseURL: URL(string: "\(mdResourceScheme):///"))
pump(until: { nav.done }, timeout: 5, "reload")
pump(until: { (eval("document.getElementById('ok').naturalWidth") as? Int ?? 0) == 2 },
     timeout: 5, "image decode with app-derived root")
print("ok: root from deletingLastPathComponent() resolves identically")

// the folder-grant bar must not appear when the image loads fine
nav.done = false
web.loadHTMLString("<img src='pic.png'><script>\(interactiveJS)</script>",
                   baseURL: URL(string: "\(mdResourceScheme):///"))
pump(until: { nav.done }, timeout: 5, "reload for negative case")
pump(until: { (eval("document.querySelector('img').complete") as? Bool) == true },
     timeout: 5, "image settle")
assert((eval("!!document.getElementById('grant-bar')") as? Bool) == false,
       "grant bar shown even though the image loaded")
print("ok: no grant bar when local images load")

print("ALL RESOURCE CHECKS PASSED")
