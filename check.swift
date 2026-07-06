// Runnable check for the rendering pipeline: runs the same bundled JS
// (marked + footnote + hljs) in JavaScriptCore against test.md and asserts
// the GFM features actually render. Usage: swift check.swift
import Foundation
import JavaScriptCore

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let res = root.appendingPathComponent("Sources/mdview/Resources")
func load(_ name: String) -> String {
    try! String(contentsOf: res.appendingPathComponent(name), encoding: .utf8)
}

let ctx = JSContext()!
ctx.exceptionHandler = { _, e in fatalError("JS error: \(e?.toString() ?? "?")") }
ctx.evaluateScript(load("marked.min.js"))
ctx.evaluateScript(load("marked-footnote.min.js"))
ctx.evaluateScript(load("highlight.min.js"))

let md = try! String(contentsOf: root.appendingPathComponent("test.md"), encoding: .utf8)
ctx.setObject(md, forKeyedSubscript: "md" as NSString)
let html = ctx.evaluateScript("marked.use({gfm:true}, markedFootnote()); marked.parse(md)")!.toString()!

for needle in ["<table>", "type=\"checkbox\"", "checked", "<del>", "<img",
               "language-swift", "<blockquote>", "<hr>", "<strong>", "<em>",
               "footnote", "href=\"https://example.com\""] {
    assert(html.contains(needle), "missing \(needle) in rendered HTML")
    print("ok: \(needle)")
}
let hl = ctx.evaluateScript(#"hljs.highlight('let x = "s"', {language:'swift'}).value"#)!.toString()!
assert(hl.contains("hljs-keyword"), "hljs produced no spans")
print("ok: hljs-keyword spans")

// Quick Look appex path: highlight at parse time (QL runs no page JS),
// same renderer hook as Sources/mdview-quicklook/PreviewProvider.swift.
let ql = ctx.evaluateScript("""
    const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    marked.use({ renderer: { code(code, info) {
        const lang = (info || '').split(/\\s+/)[0];
        let out;
        try { out = lang && hljs.getLanguage(lang) ? hljs.highlight(code, {language: lang}).value : esc(code); }
        catch (e) { out = esc(code); }
        return '<pre><code class="hljs">' + out + '</code></pre>';
    }}});
    marked.parse(md)
    """)!.toString()!
for needle in ["<table>", "hljs-keyword", "type=\"checkbox\"", "footnote"] {
    assert(ql.contains(needle), "QL path missing \(needle)")
    print("ok (ql): \(needle)")
}
print("ALL CHECKS PASSED")
