import QuickLookUI
import JavaScriptCore
import UniformTypeIdentifiers

// Quick Look data-based preview: render markdown -> final HTML here (JSC),
// because QL does not execute JS inside the previewed HTML.
// ponytail: ~30 template lines duplicated from MDViewApp.swift Renderer —
// share one source file via build.sh if a third consumer ever appears.

private func res(_ name: String) -> String {
    guard let url = Bundle.main.url(forResource: name, withExtension: nil),
          let s = try? String(contentsOf: url, encoding: .utf8)
    else { fatalError("missing bundled resource \(name)") }
    return s
}

func renderHTML(_ markdown: String) throws -> String {
    let ctx = JSContext()!
    var jsError: String?
    ctx.exceptionHandler = { _, e in jsError = e?.toString() }
    ctx.evaluateScript(res("marked.min.js"))
    ctx.evaluateScript(res("marked-footnote.min.js"))
    ctx.evaluateScript(res("highlight.min.js"))
    ctx.setObject(markdown, forKeyedSubscript: "md" as NSString)
    let body = ctx.evaluateScript("""
        const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        marked.use({ gfm: true, renderer: { code(code, info) {
            const lang = (info || '').split(/\\s+/)[0];
            let out;
            try { out = lang && hljs.getLanguage(lang) ? hljs.highlight(code, {language: lang}).value : esc(code); }
            catch (e) { out = esc(code); }
            return '<pre><code class="hljs">' + out + '</code></pre>';
        }}}, markedFootnote());
        marked.parse(md)
        """)?.toString()
    if let jsError { throw NSError(domain: "MDPreview", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: jsError]) }
    return """
    <!doctype html><html><head><meta charset="utf-8">
    <style>\(res("style.css"))</style>
    <style media="not (prefers-color-scheme: dark)">\(res("hljs-github.css"))</style>
    <style media="(prefers-color-scheme: dark)">\(res("hljs-github-dark.css"))</style>
    </head><body><article>\(body ?? "")</article></body></html>
    """
}

class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        // ponytail: relative local images won't load in QL (needs QLPreviewReply
        // attachments with cid: URLs) — upgrade path if anyone misses them.
        let md = try String(contentsOf: request.fileURL, encoding: .utf8)
        let html = try renderHTML(md)
        let reply = QLPreviewReply(dataOfContentType: .html,
                                   contentSize: CGSize(width: 800, height: 1000)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
        reply.title = request.fileURL.lastPathComponent
        return reply
    }
}
