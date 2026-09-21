# Third-party licenses

MDView bundles the following JavaScript libraries as rendering resources.
Each file is shipped unmodified with its original license header intact.

## marked v12.0.2 — MIT
Copyright (c) 2011-2024, Christopher Jeffrey.
https://github.com/markedjs/marked/blob/master/LICENSE.md

## marked-footnote v1.2.4 — MIT
https://github.com/bent10/marked-extensions/blob/main/LICENSE

## highlight.js v11.9.0 — BSD-3-Clause
Copyright (c) 2006-2023, highlight.js contributors.
https://github.com/highlightjs/highlight.js/blob/main/LICENSE

The bundled `hljs-github` / `hljs-github-dark` stylesheets are part of the
highlight.js distribution and covered by the same BSD-3-Clause license.

## Windows build (Rust crates)

The Windows shell in `windows/` is built with [Tauri](https://tauri.app) and links
the following crates, plus their transitive dependencies. Nothing is modified;
the compiled binary carries their license terms.

| Crate | Version | License |
|---|---|---|
| tauri / tauri-build | 2.11.6 / 2.6.3 | Apache-2.0 OR MIT |
| wry (webview) | 0.55.1 | Apache-2.0 OR MIT |
| tao (windowing) | 0.35.3 | Apache-2.0 |
| rfd (file dialogs) | 0.15.4 | MIT |
| base64 | 0.21.7 | MIT OR Apache-2.0 |
| open | 5.4.4 | MIT |

Where a crate is dual-licensed, MDView uses it under the MIT terms. Across the
full dependency tree the licenses are MIT, Apache-2.0, BSD, ISC, Zlib,
Unicode-3.0 and Unlicense, with these exceptions:

- **MPL-2.0** — `cssparser`, `cssparser-macros`, `selectors`, `dtoa-short`,
  `option-ext` (Tauri's CSS handling, from the Servo project). MPL-2.0 is
  file-level: it obliges publication only of changes to those files, and none
  are made.
- `r-efi` is offered under MIT OR Apache-2.0 OR LGPL-2.1-or-later; MIT applies.

Regenerate this list with `cargo metadata` in `windows/src-tauri`.
