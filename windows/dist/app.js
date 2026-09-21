// MDView for Windows — the glue around the shared renderer and edits.js.
// Anything markdown-related lives in assets/edits.js, shared verbatim with the
// macOS app; this file only wires it to a textarea, a toolbar and the disk.
'use strict';

const invoke = window.__TAURI__.core.invoke;
const $ = id => document.getElementById(id);

const state = { path: null, text: '', editing: false, dirty: false };

// --- shared interactive.js talks to the "webkit" bridge on macOS; give it the
// same shape here so that file can be reused without a single change.
window.webkit = { messageHandlers: { bridge: { postMessage: onBridge } } };

function onBridge(msg) {
  if (msg.kind === 'toggle') {
    const updated = MDEdits.toggleTask(state.text, msg.index);
    if (updated === state.text) return;
    state.text = updated;          // the DOM checkbox already flipped
    markDirty();
  } else if (msg.kind === 'copy') {
    navigator.clipboard.writeText(msg.text).catch(() => {});
  }
  // 'grantAccess' is macOS sandbox only and never fires here
}

// --- rendering ----------------------------------------------------------

marked.use({ gfm: true }, markedFootnote());

let interactiveSource = null;

async function render() {
  $('c').innerHTML = marked.parse(state.text);
  document.querySelectorAll('#c pre code').forEach(el => hljs.highlightElement(el));
  await inlineImages();

  // interactive.js is an IIFE; re-running it re-binds the new DOM
  if (interactiveSource === null) {
    interactiveSource = await fetch('assets/interactive.js').then(r => r.text());
  }
  eval(interactiveSource);
}

const dirOf = p => p.replace(/[\\/][^\\/]*$/, '');

// The webview cannot read the document's folder, so relative images are
// inlined as data: URLs through the Rust side.
async function inlineImages() {
  if (!state.path) return;
  const dir = dirOf(state.path);
  const imgs = [...document.querySelectorAll('#c img')].filter(img => {
    const raw = img.getAttribute('src') || '';
    return raw && !/^[a-z][a-z0-9+.-]*:|^\/\//i.test(raw);
  });
  await Promise.all(imgs.map(async img => {
    const raw = img.getAttribute('src');
    try {
      img.src = await invoke('read_data_url', { path: dir + '/' + raw });
    } catch {
      img.alt = (img.alt || '') + ' (image not found: ' + raw + ')';
    }
  }));
}

// Links leave the app rather than replacing the preview.
document.addEventListener('click', e => {
  const a = e.target.closest('a');
  if (!a) return;
  const href = a.getAttribute('href') || '';
  if (/^(https?:|mailto:)/i.test(href)) {
    e.preventDefault();
    invoke('open_external', { url: href }).catch(() => {});
  }
});

// --- document -----------------------------------------------------------

function markDirty() {
  state.dirty = true;
  $('name').classList.add('dirty');
}

function setDocument(path, text) {
  state.path = path;
  state.text = text;
  state.dirty = false;
  $('name').textContent = path ? path.split(/[\\/]/).pop() : 'Untitled';
  $('name').classList.remove('dirty');
  $('editor').value = text;
  render();
}

async function openFile() {
  const path = await invoke('open_dialog');
  if (!path) return;
  setDocument(path, await invoke('read_text', { path }));
}

async function save() {
  let path = state.path;
  if (!path) {
    path = await invoke('save_dialog');
    if (!path) return;
    state.path = path;
    $('name').textContent = path.split(/[\\/]/).pop();
  }
  await invoke('write_text', { path, contents: state.text });
  state.dirty = false;
  $('name').classList.remove('dirty');
}

function setEditing(on) {
  state.editing = on;
  document.body.classList.toggle('editing', on);
  $('toggle').textContent = on ? 'Preview' : 'Edit';
  if (on) $('editor').focus();
  else render();
}

// --- editing ------------------------------------------------------------

const editor = $('editor');

editor.addEventListener('input', () => {
  state.text = editor.value;
  markDirty();
});

function applyEdit(kind, arg) {
  const level = kind.startsWith('heading') ? parseInt(kind.slice(7), 10) : arg;
  const op = kind.startsWith('heading') ? 'heading' : kind;
  const r = MDEdits.apply(op, editor.value, editor.selectionStart, editor.selectionEnd, level);
  if (!r) return;
  editor.value = r.text;
  editor.setSelectionRange(r.start, r.end);
  state.text = r.text;
  markDirty();
  editor.focus();
}

editor.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    const r = MDEdits.continueList(editor.value, editor.selectionStart);
    if (!r) return;                       // not a list: let the newline happen
    e.preventDefault();
    editor.value = r.text;
    editor.setSelectionRange(r.start, r.end);
    state.text = r.text;
    markDirty();
    return;
  }
  if (e.key === 'Tab') {
    e.preventDefault();
    applyEdit(e.shiftKey ? 'outdent' : 'indent');
  }
});

// Pasting a URL over a selection makes a link; pasting an image saves it
// next to the document, mirroring GitHub's upload.
editor.addEventListener('paste', async e => {
  const items = [...(e.clipboardData?.items || [])];
  const image = items.find(i => i.type.startsWith('image/'));
  if (image && state.path) {
    e.preventDefault();
    const file = image.getAsFile();
    const buf = new Uint8Array(await file.arrayBuffer());
    let binary = '';
    buf.forEach(b => { binary += String.fromCharCode(b); });
    const ext = (image.type.split('/')[1] || 'png').replace('jpeg', 'jpg');
    const name = 'pasted-' + stamp() + '.' + ext;
    try {
      const rel = await invoke('write_image', {
        dir: dirOf(state.path), name, dataBase64: btoa(binary),
      });
      insertAtCursor('![](' + rel + ')');
    } catch { /* leave the paste alone if it could not be written */ }
    return;
  }
  const text = (e.clipboardData?.getData('text') || '').trim();
  if (text && editor.selectionStart !== editor.selectionEnd &&
      /^(https?:\/\/|mailto:)\S+$/.test(text)) {
    e.preventDefault();
    applyEdit('link', text);
  }
});

function insertAtCursor(s) {
  const start = editor.selectionStart, end = editor.selectionEnd;
  editor.value = editor.value.slice(0, start) + s + editor.value.slice(end);
  editor.setSelectionRange(start + s.length, start + s.length);
  state.text = editor.value;
  markDirty();
}

function stamp() {
  const p = n => String(n).padStart(2, '0');
  const d = new Date();
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

// --- chrome -------------------------------------------------------------

$('open').onclick = openFile;
$('save').onclick = save;
$('toggle').onclick = () => setEditing(!state.editing);
document.querySelectorAll('.fmt[data-kind]').forEach(b => {
  b.onclick = () => applyEdit(b.dataset.kind);
});

const SHORTCUTS = {
  'b': 'bold', 'i': 'italic', 'k': 'link', 'e': 'code',
  '1': 'heading1', '2': 'heading2', '3': 'heading3',
};
const SHIFTED = { 'x': 'strike', '.': 'quote', '8': 'bullet', '7': 'number', 'l': 'task' };

document.addEventListener('keydown', e => {
  if (!e.ctrlKey && !e.metaKey) return;
  const key = e.key.toLowerCase();
  if (key === 's') { e.preventDefault(); save(); return; }
  if (key === 'o') { e.preventDefault(); openFile(); return; }
  if (key === 'e' && e.shiftKey) { e.preventDefault(); setEditing(!state.editing); return; }
  if (!state.editing) return;
  const kind = e.shiftKey ? SHIFTED[key] : SHORTCUTS[key];
  if (kind) { e.preventDefault(); applyEdit(kind); }
});

// --- start --------------------------------------------------------------

(async () => {
  const path = await invoke('launch_file');
  if (path) setDocument(path, await invoke('read_text', { path }));
  else setDocument(null, '# MDView\n\nOpen a Markdown file to get started.\n');
})();
