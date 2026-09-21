// End-to-end check for the interactive preview bridge. Loads the REAL bundled
// marked + interactive.js offscreen, simulates user clicks, and asserts the
// JS posts the right messages to the Swift handler.
// Usage: swift check-interactive.swift
import AppKit
import WebKit

let res = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/mdview/Resources")
func load(_ f: String) -> String { try! String(contentsOf: res.appendingPathComponent(f), encoding: .utf8) }

let md = "- [ ] one\n- [ ] two\n\n```\ncode here\n```\n\n![pic](pic.png)\n"
let mdJSON = String(data: try! JSONSerialization.data(withJSONObject: md, options: .fragmentsAllowed),
                    encoding: .utf8)!.replacingOccurrences(of: "</", with: "<\\/")

let html = """
<!doctype html><html><head><meta charset="utf-8"></head><body><article id="c"></article>
<script>\(load("marked.min.js"))</script>
<script>
document.getElementById("c").innerHTML = marked.parse(\(mdJSON));
</script>
<script>\(load("interactive.js"))</script>
</body></html>
"""

final class Handler: NSObject, WKScriptMessageHandler {
    var messages: [[String: Any]] = []
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        if let d = m.body as? [String: Any] { messages.append(d) }
    }
}

// Stands in for a sandbox denial: every local resource request fails.
final class DenyAll: NSObject, WKURLSchemeHandler {
    func webView(_ w: WKWebView, start task: WKURLSchemeTask) {
        task.didFailWithError(URLError(.noPermissionsToReadFile))
    }
    func webView(_ w: WKWebView, stop task: WKURLSchemeTask) {}
}

let handler = Handler()
let config = WKWebViewConfiguration()
config.setURLSchemeHandler(DenyAll(), forURLScheme: "mdres")
config.userContentController.add(handler, name: "bridge")
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), configuration: config)

final class Nav: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done = true }
}
let nav = Nav()
web.navigationDelegate = nav
web.loadHTMLString(html, baseURL: URL(string: "mdres:///"))

func pump(until cond: () -> Bool, timeout: TimeInterval, _ label: String) {
    let deadline = Date().addingTimeInterval(timeout)
    while !cond() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    assert(cond(), "timed out waiting for: \(label)")
}

pump(until: { nav.done }, timeout: 5, "page load")

func js(_ s: String) {
    var finished = false
    web.evaluateJavaScript(s) { _, err in
        if let err = err { fatalError("JS error in \(s.prefix(40)): \(err)") }
        finished = true
    }
    pump(until: { finished }, timeout: 5, "js eval")
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

// two checkboxes should be present and enabled
js("if (document.querySelectorAll('input[type=checkbox]').length !== 2) throw 'expected 2 boxes'")
js("if (document.querySelectorAll('input[type=checkbox]:disabled').length !== 0) throw 'boxes still disabled'")
print("ok: 2 task checkboxes rendered and enabled")

// one copy button, code fence not counted as a checkbox
js("if (document.querySelectorAll('.copy-btn').length !== 1) throw 'expected 1 copy button'")
print("ok: copy button added to the code block")

// click the SECOND checkbox -> expect {kind:toggle, index:1}
js("document.querySelectorAll('input[type=checkbox]')[1].click()")
pump(until: { !handler.messages.isEmpty }, timeout: 5, "toggle message")
let t = handler.messages[0]
assert(t["kind"] as? String == "toggle" && t["index"] as? Int == 1,
       "wrong toggle message: \(t)")
print("ok: clicking box #2 posts {kind:toggle, index:1}")

// click the copy button -> expect {kind:copy, text:"code here"} (trailing newline trimmed by innerText)
handler.messages.removeAll()
js("document.querySelector('.copy-btn').click()")
pump(until: { !handler.messages.isEmpty }, timeout: 5, "copy message")
let c = handler.messages[0]
assert(c["kind"] as? String == "copy", "wrong copy kind: \(c)")
assert((c["text"] as? String)?.contains("code here") == true, "copy text missing code: \(c)")
print("ok: clicking copy posts {kind:copy, text:'code here'}")

// a local image that fails to load must surface the folder-grant offer
pump(until: { (eval("!!document.getElementById('grant-bar')") as? Bool) == true },
     timeout: 5, "grant bar")
print("ok: failed local image offers 'Show local images…'")

handler.messages.removeAll()
js("document.querySelector('#grant-bar button').click()")
pump(until: { !handler.messages.isEmpty }, timeout: 5, "grantAccess message")
assert(handler.messages[0]["kind"] as? String == "grantAccess",
       "wrong grant message: \(handler.messages[0])")
print("ok: clicking it posts {kind:grantAccess}")

print("ALL INTERACTIVE CHECKS PASSED")
