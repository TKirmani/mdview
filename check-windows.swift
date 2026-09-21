// Drives the Windows frontend (windows/dist) headlessly in a WebView with the
// Tauri backend stubbed out, so the shared edits.js + interactive.js wiring is
// verified on this machine. WebView2-specific behaviour still needs Windows.
// Usage: swift check-windows.swift
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let dist = root.appendingPathComponent("windows/dist")
// Assets come from the source of truth, not windows/dist/assets — build.rs
// copies them there, so this check does not need cargo to have run first.
let shared = root.appendingPathComponent("Sources/mdview/Resources")

func read(_ rel: String) -> String {
    let base = rel.hasPrefix("assets/") ? shared : dist
    let name = rel.hasPrefix("assets/") ? String(rel.dropFirst("assets/".count)) : rel
    return try! String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
}

// Inline every asset: a file:// page cannot pull in subresources.
var html = read("index.html")
for name in ["marked.min.js", "marked-footnote.min.js", "highlight.min.js", "edits.js"] {
    html = html.replacingOccurrences(of: "<script src=\"assets/\(name)\"></script>",
                                     with: "<script>\(read("assets/" + name))</script>")
}
// <link rel="stylesheet" href="assets/X" [media=...]> -> inline <style>
let linkRE = try! NSRegularExpression(pattern: "<link[^>]*href=\"assets/([^\"]+)\"[^>]*>")
while let m = linkRE.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
    let file = String(html[Range(m.range(at: 1), in: html)!])
    html = html.replacingCharacters(in: Range(m.range, in: html)!,
                                    with: "<style>" + read("assets/" + file) + "</style>")
}

let doc = "# Title\n\n- [ ] one\n- [ ] two\n\n```\ncode here\n```\n"
func jsString(_ s: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed),
           encoding: .utf8)!.replacingOccurrences(of: "</", with: "<\\/")
}

// Stub the Tauri bridge and fetch, then the real app.js.
let stub = """
<script>
window.__calls = [];
window.__TAURI__ = { core: { invoke: async (cmd, args) => {
  window.__calls.push({ cmd: cmd, args: args });
  if (cmd === 'launch_file') return '/tmp/doc/note.md';
  if (cmd === 'read_text') return \(jsString(doc));
  if (cmd === 'write_image') return 'images/pasted-test.png';
  if (cmd === 'read_data_url') return 'data:image/png;base64,';
  return null;
}}};
window.fetch = async () => ({ text: async () => \(jsString(read("assets/interactive.js"))) });
</script>
<script>\(read("app.js"))</script>
"""
html = html.replacingOccurrences(of: "<script src=\"app.js\"></script>", with: stub)
assert(!html.contains("src=\"assets/") && !html.contains("href=\"assets/"),
       "an asset tag was left unresolved")

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
final class Nav: NSObject, WKNavigationDelegate {
    var done = false
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { done = true }
}
let nav = Nav()
web.navigationDelegate = nav
web.loadHTMLString(html, baseURL: nil)

func pump(until cond: () -> Bool, timeout: TimeInterval, _ label: String) {
    let deadline = Date().addingTimeInterval(timeout)
    while !cond() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    assert(cond(), "timed out waiting for: \(label)")
}

func eval(_ s: String) -> Any? {
    var out: Any?; var done = false
    web.evaluateJavaScript(s) { v, e in
        if let e = e { fatalError("JS error in \(s.prefix(60)): \(e)") }
        out = v; done = true
    }
    pump(until: { done }, timeout: 5, "js eval")
    return out
}

var failures = 0
func expect(_ label: String, _ got: Any?, _ want: String) {
    let g = "\(got ?? "nil")"
    if g == want { print("ok: \(label)") }
    else { print("FAIL \(label)\n   got: \(g.debugDescription)\n  want: \(want.debugDescription)"); failures += 1 }
}

pump(until: { nav.done }, timeout: 5, "page load")
// the launch_file -> read_text -> render chain is async
pump(until: { (eval("document.querySelector('#c h1') !== null") as? Bool) == true }, timeout: 5, "first render")

expect("opens the file it was launched with", eval("document.querySelector('#c h1').textContent"), "Title")
expect("renders task checkboxes", eval("document.querySelectorAll('#c input[type=checkbox]').length"), "2")
expect("shows the file name", eval("document.getElementById('name').textContent"), "note.md")

// interactive.js was re-run against the fresh DOM
expect("copy button added by the shared interactive.js",
       eval("document.querySelectorAll('#c .copy-btn').length"), "1")
expect("checkboxes enabled", eval("document.querySelectorAll('#c input:disabled').length"), "0")

// ticking a box must write through to the document text
_ = eval("document.querySelectorAll('#c input[type=checkbox]')[1].click()")
pump(until: { (eval("state.text.indexOf('- [x] two') !== -1") as? Bool) == true }, timeout: 5, "task write-back")
print("ok: ticking a preview checkbox updates the source")
expect("marked dirty after the toggle", eval("state.dirty"), "1")

// --- editing ---
_ = eval("document.getElementById('toggle').click()")
expect("switches to edit mode", eval("document.body.classList.contains('editing')"), "1")
expect("editor holds the source", eval("editor.value.indexOf('# Title') === 0"), "1")

// format a selection with the toolbar
_ = eval("editor.setSelectionRange(2, 7)")   // "Title"
_ = eval("document.querySelector('.fmt[data-kind=bold]').click()")
expect("toolbar bold wraps the selection", eval("editor.value.indexOf('# **Title**') === 0"), "1")

// heading buttons carry their level
_ = eval("editor.value = 'plain'; editor.setSelectionRange(0, 5); state.text = 'plain'")
_ = eval("document.querySelector('.fmt[data-kind=heading2]').click()")
expect("heading 2 from the toolbar", eval("editor.value"), "## plain")

// Enter continues a list, via the real keydown handler
_ = eval("editor.value = '- one'; editor.setSelectionRange(5, 5)")
_ = eval("editor.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true, cancelable:true}))")
expect("Enter continues the list", eval("JSON.stringify(editor.value)"), "\"- one\\n- \"")

// Tab indents inside the editor
_ = eval("editor.value = '- one'; editor.setSelectionRange(0, 5)")
_ = eval("editor.dispatchEvent(new KeyboardEvent('keydown', {key:'Tab', bubbles:true, cancelable:true}))")
expect("Tab indents", eval("JSON.stringify(editor.value)"), "\"  - one\"")

// Ctrl+S reaches the backend with the current text
_ = eval("window.__calls = []")
_ = eval("document.dispatchEvent(new KeyboardEvent('keydown', {key:'s', ctrlKey:true, bubbles:true, cancelable:true}))")
pump(until: { (eval("window.__calls.some(c => c.cmd === 'write_text')") as? Bool) == true }, timeout: 5, "save")
expect("Ctrl+S saves to the launched path",
       eval("window.__calls.find(c => c.cmd === 'write_text').args.path"), "/tmp/doc/note.md")

print(failures == 0 ? "ALL WINDOWS FRONTEND CHECKS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
