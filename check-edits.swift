// Checks the shared edits.js through JavaScriptCore — the same path the macOS
// app uses. Selections are written «like this» in both input and expectation.
// Usage: swift check-edits.swift
import Foundation
import JavaScriptCore

let js = try! String(contentsOf: URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/mdview/Resources/edits.js"), encoding: .utf8)

let ctx = JSContext()!
ctx.exceptionHandler = { _, e in fatalError("JS exception: \(e?.toString() ?? "?")") }
ctx.evaluateScript(js)

/// "a«bc»d" -> ("abcd", 1, 3). Offsets are UTF-16 units, matching both
/// JavaScript strings and NSRange, so emoji line up the way the app sees them.
func parse(_ s: String) -> (String, Int, Int) {
    let ns = NSMutableString(string: s)
    let o = ns.range(of: "«")
    guard o.location != NSNotFound else { return (s, ns.length, ns.length) }
    let start = o.location
    ns.deleteCharacters(in: o)
    let c = ns.range(of: "»")
    guard c.location != NSNotFound else { return (ns as String, start, start) }
    let end = c.location
    ns.deleteCharacters(in: c)
    return (ns as String, start, end)
}

func mark(_ text: String, _ start: Int, _ end: Int) -> String {
    let ns = NSMutableString(string: text)
    ns.insert("»", at: end)
    ns.insert("«", at: start)
    return ns as String
}

var failures = 0

func check(_ label: String, _ kind: String, _ input: String, _ expected: String, arg: Any? = nil) {
    let (text, s, e) = parse(input)
    let fn = ctx.objectForKeyedSubscript("MDEdits")!.objectForKeyedSubscript("apply")!
    let r = fn.call(withArguments: [kind, text, s, e, arg as Any])!
    guard !r.isNull, !r.isUndefined else {
        print("FAIL \(label): op returned null"); failures += 1; return
    }
    let got = mark(r.objectForKeyedSubscript("text").toString(),
                   Int(r.objectForKeyedSubscript("start").toInt32()),
                   Int(r.objectForKeyedSubscript("end").toInt32()))
    if got == expected { print("ok: \(label)") }
    else { print("FAIL \(label)\n   got: \(got.debugDescription)\n  want: \(expected.debugDescription)"); failures += 1 }
}

func checkContinue(_ label: String, _ input: String, _ expected: String?) {
    let (text, s, _) = parse(input)
    let fn = ctx.objectForKeyedSubscript("MDEdits")!.objectForKeyedSubscript("continueList")!
    let r = fn.call(withArguments: [text, s])!
    if r.isNull || r.isUndefined {
        if expected == nil { print("ok: \(label)") }
        else { print("FAIL \(label): returned null, wanted \(expected!.debugDescription)"); failures += 1 }
        return
    }
    let got = mark(r.objectForKeyedSubscript("text").toString(),
                   Int(r.objectForKeyedSubscript("start").toInt32()),
                   Int(r.objectForKeyedSubscript("end").toInt32()))
    if got == expected { print("ok: \(label)") }
    else { print("FAIL \(label)\n   got: \(got.debugDescription)\n  want: \(expected?.debugDescription ?? "nil")"); failures += 1 }
}

// --- inline wrapping ---
check("bold, no selection", "bold", "«»", "**«»**")
check("bold wraps selection", "bold", "say «hi» there", "say **«hi»** there")
check("bold unwraps from outside", "bold", "**«hi»**", "«hi»")
check("bold unwraps from inside", "bold", "«**hi**»", "«hi»")
check("italic uses _", "italic", "«hi»", "_«hi»_")
check("inline code", "code", "«hi»", "`«hi»`")
check("strikethrough", "strike", "«hi»", "~~«hi»~~")
// a surrogate pair must not shift the offsets (UTF-16, not characters)
check("emoji before selection", "bold", "a👍 «hi»", "a👍 **«hi»**")
check("emoji inside selection", "bold", "«👍ok»", "**«👍ok»**")

// Line-prefix ops keep the whole reformatted span selected, as GitHub does.
// --- line prefixes ---
check("bullet one line", "bullet", "«one»", "«- one»")
check("bullet multiple lines", "bullet", "«one\ntwo»", "«- one\n- two»")
check("bullet toggles off", "bullet", "«- one»", "«one»")
check("bullet replaces numbered", "bullet", "«1. one»", "«- one»")
check("numbered increments", "number", "«one\ntwo\nthree»", "«1. one\n2. two\n3. three»")
check("task list", "task", "«one»", "«- [ ] one»")
check("quote", "quote", "«one»", "«> one»")
check("quote toggles off", "quote", "«> one»", "«one»")
check("blank lines untouched", "bullet", "«one\n\ntwo»", "«- one\n\n- two»")

// --- headings ---
check("heading level 2", "heading", "«title»", "«## title»", arg: 2)
check("heading toggles off", "heading", "«## title»", "«title»", arg: 2)
check("heading replaces level", "heading", "«# title»", "«## title»", arg: 2)

// With no URL supplied the caret parks inside the empty parens, ready to type one.
// --- link ---
check("link, no selection", "link", "«»", "[](«»)")
check("link wraps selection", "link", "«text»", "[text](«»)")
check("link when selection is a url", "link", "«https://x.com»", "[«»](https://x.com)")
check("link from pasted url", "link", "«text»", "[text](https://x.com)«»", arg: "https://x.com")

// --- blocks ---
check("code block", "codeblock", "«hi»", "```«»\nhi\n```")
check("table at line start", "table", "«»", "| Column | Column |\n| --- | --- |\n|  |  |\n«»")

// --- indent ---
check("indent", "indent", "«one»", "«  one»")
check("outdent", "outdent", "«  one»", "«one»")

// --- Enter handling ---
checkContinue("continues a bullet", "- one«»", "- one\n- «»")
checkContinue("increments a numbered item", "1. one«»", "1. one\n2. «»")
checkContinue("new task starts unchecked", "- [x] done«»", "- [x] done\n- [ ] «»")
checkContinue("empty item ends the list", "- «»", "«»")
checkContinue("plain text is not a list", "hello«»", nil)
checkContinue("keeps nested indent", "  - one«»", "  - one\n  - «»")

// --- task list toggling (shared with the preview checkboxes) ---
func checkTask(_ label: String, _ input: String, _ index: Int, _ expected: String) {
    let fn = ctx.objectForKeyedSubscript("MDEdits")!.objectForKeyedSubscript("toggleTask")!
    let got = fn.call(withArguments: [input, index])!.toString()!
    if got == expected { print("ok: \(label)") }
    else { print("FAIL \(label)\n   got: \(got.debugDescription)\n  want: \(expected.debugDescription)"); failures += 1 }
}

checkTask("ticks a box", "- [ ] a", 0, "- [x] a")
checkTask("unticks a box", "- [x] a", 0, "- [ ] a")
checkTask("uppercase X counts as ticked", "- [X] a", 0, "- [ ] a")
checkTask("indexes the right item", "- [ ] a\n- [ ] b", 1, "- [ ] a\n- [x] b")
checkTask("ordered list items count", "1. [ ] a", 0, "1. [x] a")
checkTask("indented items count", "   - [ ] a", 0, "   - [x] a")
checkTask("fenced code is skipped", "```\n- [ ] fake\n```\n- [ ] real", 0, "```\n- [ ] fake\n```\n- [x] real")
checkTask("[x] in prose is not a task", "see [x] here\n- [ ] a", 0, "see [x] here\n- [x] a")
checkTask("out of range changes nothing", "- [ ] a", 5, "- [ ] a")

print(failures == 0 ? "ALL EDIT CHECKS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
