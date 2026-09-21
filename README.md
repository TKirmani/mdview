<p align="center"><img src="AppIcon-1024.png" width="128" alt="MDView icon"></p>

# MDView

[![CI](https://github.com/TKirmani/mdview/actions/workflows/ci.yml/badge.svg)](https://github.com/TKirmani/mdview/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Windows%2010%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A tiny native macOS Markdown viewer/editor, with a Windows build. **&lt;1 MB on macOS** — no Electron, no runtimes.

- **Double-click any `.md` file** → rendered preview (registers as a Markdown editor with Finder)
- **Complete GFM rendering**: tables, task lists, images, strikethrough, footnotes, syntax-highlighted code blocks
- **Interactive preview**: tick task-list checkboxes (written straight back to the file), one-click copy on every code block, links open in your browser
- **Edit mode**: ⇧⌘E toggles a plain-text editor, ⌘S saves (autosave/recents come from macOS)
- **GitHub-style editing**: a format bar and a Format menu — bold, italic, strikethrough, code, links, headings, quotes, bulleted/numbered/task lists, tables. Enter continues a list, Tab indents it, a pasted URL wraps the selection in a link, and a pasted or dropped image is saved into `./images` next to the document
- **Find & replace** (edit mode): ⌘F find, ⌘⌥F replace — the native macOS find bar, regex included
- **Quick Look extension**: spacebar previews and Finder's preview pane render through the same pipeline
- GitHub-style light/dark theme, follows the system appearance
- Opens maximized; quits when the last window closes

Rendering is [marked](https://github.com/markedjs/marked) + [highlight.js](https://github.com/highlightjs/highlight.js) running locally (bundled, zero network at runtime) inside a WKWebView / JavaScriptCore. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## Build

Requires macOS 13+ and the Xcode Command Line Tools (full Xcode not needed).

```sh
./build.sh
```

Produces `build/MDView.app` (ad-hoc codesigned).

```sh
./build.sh --sandbox
```

Same app signed with the App Sandbox, as an App Store build must be. Local images
then need a one-time folder grant (the preview offers a **Show local images…**
button when one fails), which is why the sandbox is off by default.

## Install

1. Copy `build/MDView.app` to `/Applications` and launch it once.
2. Make it the default for Markdown: right-click any `.md` file → Get Info → Open with → MDView → **Change All**.
3. Quick Look: if spacebar still shows plain text, enable **MDView** under System Settings → General → Login Items & Extensions → Quick Look.

> **Downloaded a prebuilt .app?** It is ad-hoc signed, so Gatekeeper will block the first launch: right-click → Open → Open (or `xattr -d com.apple.quarantine MDView.app`). Building from source avoids this.

## Windows

`windows/` is a [Tauri](https://tauri.app) shell (Rust + the system WebView2) around
the *same* renderer and the same editing code — `windows/src-tauri/build.rs` copies
`Sources/mdview/Resources/` in at build time, so there is exactly one copy of
marked, highlight.js, the stylesheet and `edits.js` in the repository.

```sh
cd windows/src-tauri
cargo build --release          # or: cargo tauri build  (for an .msi/.exe installer)
```

Roughly a 4 MB binary rather than Electron's ~150 MB. Before bundling installers,
generate the icon set once with `cargo tauri icon ../../AppIcon-1024.png`.

## Known limits

- Relative-path images render in the app, but not in Quick Look previews (needs QL attachments — noted in code).
- Under the sandbox, relative images need the folder granted once — the sandbox permits reading the opened `.md` file only, not its siblings.
- arm64 only as built; Intel needs a rebuild on x86_64.
- The Windows build has no find bar yet (macOS uses the native one) and no Quick Look equivalent.

## License

MIT — see [LICENSE](LICENSE). Bundled renderer libraries are MIT/BSD, see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
