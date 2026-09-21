// MDView for Windows: a Tauri shell around the same renderer and the same
// edits.js the macOS app uses. All markdown logic lives in JavaScript; this
// side only touches the filesystem.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use base64::Engine;

#[tauri::command]
fn read_text(path: String) -> Result<String, String> {
    std::fs::read_to_string(&path).map_err(|e| format!("{path}: {e}"))
}

#[tauri::command]
fn write_text(path: String, contents: String) -> Result<(), String> {
    std::fs::write(&path, contents).map_err(|e| format!("{path}: {e}"))
}

/// Relative images are read through here and inlined as data: URLs — the
/// webview has no access to the document's folder otherwise.
#[tauri::command]
fn read_data_url(path: String) -> Result<String, String> {
    let bytes = std::fs::read(&path).map_err(|e| format!("{path}: {e}"))?;
    let mime = match std::path::Path::new(&path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "bmp" => "image/bmp",
        _ => "application/octet-stream",
    };
    Ok(format!(
        "data:{};base64,{}",
        mime,
        base64::engine::general_purpose::STANDARD.encode(bytes)
    ))
}

/// Writes a pasted or dropped image into ./images beside the document.
#[tauri::command]
fn write_image(dir: String, name: String, data_base64: String) -> Result<String, String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(data_base64.as_bytes())
        .map_err(|e| e.to_string())?;
    let folder = std::path::Path::new(&dir).join("images");
    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    std::fs::write(folder.join(&name), bytes).map_err(|e| e.to_string())?;
    Ok(format!("images/{name}"))
}

#[tauri::command]
fn open_dialog() -> Option<String> {
    rfd::FileDialog::new()
        .add_filter("Markdown", &["md", "markdown", "mdown"])
        .pick_file()
        .map(|p| p.to_string_lossy().into_owned())
}

#[tauri::command]
fn save_dialog() -> Option<String> {
    rfd::FileDialog::new()
        .add_filter("Markdown", &["md"])
        .set_file_name("Untitled.md")
        .save_file()
        .map(|p| p.to_string_lossy().into_owned())
}

/// Links in the preview open in the default browser, not in the app window.
#[tauri::command]
fn open_external(url: String) -> Result<(), String> {
    open::that(&url).map_err(|e| e.to_string())
}

/// The file a double-click in Explorer passed on the command line.
#[tauri::command]
fn launch_file() -> Option<String> {
    std::env::args().nth(1).filter(|a| !a.starts_with('-'))
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            read_text,
            write_text,
            read_data_url,
            write_image,
            open_dialog,
            save_dialog,
            launch_file,
            open_external
        ])
        .run(tauri::generate_context!())
        .expect("failed to start MDView");
}
