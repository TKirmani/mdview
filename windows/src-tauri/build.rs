use std::path::Path;

// The renderer (marked, highlight.js, the stylesheet, interactive.js and
// edits.js) is shared verbatim with the macOS app. Copy it in at build time so
// there is exactly one copy in the repository.
fn main() {
    let shared = Path::new("../../Sources/mdview/Resources");
    let dest = Path::new("../dist/assets");

    std::fs::create_dir_all(dest).expect("could not create dist/assets");
    let entries = std::fs::read_dir(shared)
        .expect("shared resources not found — run from windows/src-tauri");
    for entry in entries {
        let path = entry.expect("unreadable entry").path();
        if path.is_file() {
            let name = path.file_name().expect("no file name");
            std::fs::copy(&path, dest.join(name)).expect("could not copy shared resource");
        }
    }
    println!("cargo:rerun-if-changed=../../Sources/mdview/Resources");

    tauri_build::build()
}
