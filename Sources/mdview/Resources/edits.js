// Markdown editing operations, shared by the macOS app (evaluated through
// JavaScriptCore) and the Tauri/Windows shell (loaded directly).
//
// Pure string math on purpose: no DOM, no NSTextView, no platform types.
// Every op takes (text, start, end, arg) and returns { text, start, end },
// where start/end are character offsets of the selection.
(function (global) {
  'use strict';

  function splice(text, from, to, replacement) {
    return text.slice(0, from) + replacement + text.slice(to);
  }

  function lineStart(text, pos) { return text.lastIndexOf('\n', pos - 1) + 1; }

  function lineEnd(text, pos) {
    const i = text.indexOf('\n', pos);
    return i === -1 ? text.length : i;
  }

  // Expand a selection to cover whole lines. A selection ending exactly on a
  // newline must not drag in the following line.
  function lineSpan(text, start, end) {
    let e = end;
    if (e > start && text[e - 1] === '\n') e -= 1;
    return [lineStart(text, start), lineEnd(text, e)];
  }

  // Any list marker: bullet, ordered, or task. Group 1 is the indent.
  const MARKER = /^(\s*)(?:[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)/;
  const QUOTE = /^(\s*)>\s?/;
  const HEADING = /^(\s*)#{1,6}\s+/;

  // --- inline wrapping: bold, italic, strikethrough, inline code ----------

  function wrap(text, start, end, marker) {
    const sel = text.slice(start, end);
    const n = marker.length;

    // markers sit just outside the selection -> unwrap
    if (text.slice(start - n, start) === marker && text.slice(end, end + n) === marker) {
      return { text: splice(text, start - n, end + n, sel), start: start - n, end: end - n };
    }
    // markers are inside the selection -> unwrap
    if (sel.length >= 2 * n && sel.slice(0, n) === marker && sel.slice(-n) === marker) {
      const inner = sel.slice(n, sel.length - n);
      return { text: splice(text, start, end, inner), start: start, end: start + inner.length };
    }
    return {
      text: splice(text, start, end, marker + sel + marker),
      start: start + n,
      end: end + n,
    };
  }

  // --- line prefixes: quote, lists, headings ------------------------------

  // `strip` removes an existing prefix of this kind; `foreign` removes a
  // competing marker so toggling bullet -> numbered replaces instead of stacking.
  function prefixLines(text, start, end, make, strip, foreign) {
    const [a, b] = lineSpan(text, start, end);
    const lines = text.slice(a, b).split('\n');
    const on = lines.every(l => l.trim() === '' || strip.test(l));

    const out = lines.map((line, i) => {
      if (line.trim() === '') return line;
      if (on) return line.replace(strip, '$1');
      let bare = line.replace(strip, '$1');
      if (foreign) bare = bare.replace(foreign, '$1');
      const indent = (bare.match(/^\s*/) || [''])[0];
      return indent + make(i) + bare.slice(indent.length);
    }).join('\n');

    return { text: splice(text, a, b, out), start: a, end: a + out.length };
  }

  // --- link ---------------------------------------------------------------

  function link(text, start, end, url) {
    const sel = text.slice(start, end);
    const selIsURL = /^(https?:\/\/|mailto:)\S+$/.test(sel.trim());

    // pasting a URL over selected text
    if (url) {
      const out = '[' + sel + '](' + url + ')';
      const caret = start + out.length;
      return { text: splice(text, start, end, out), start: caret, end: caret };
    }
    // the selection is itself a URL -> caret goes in the label
    if (selIsURL) {
      const out = '[](' + sel.trim() + ')';
      return { text: splice(text, start, end, out), start: start + 1, end: start + 1 };
    }
    // otherwise caret goes in the empty parens
    const out = '[' + sel + ']()';
    const caret = start + sel.length + 3;
    return { text: splice(text, start, end, out), start: caret, end: caret };
  }

  // --- block ops ----------------------------------------------------------

  function codeBlock(text, start, end) {
    const [a, b] = lineSpan(text, start, end);
    const body = text.slice(a, b);
    const fenced = '```\n' + body + '\n```';
    return { text: splice(text, a, b, fenced), start: a + 3, end: a + 3 }; // caret on the language slot
  }

  function table(text, start, end) {
    const rows = '| Column | Column |\n| --- | --- |\n|  |  |';
    const atLineStart = start === lineStart(text, start);
    const block = (atLineStart ? '' : '\n') + rows + '\n';
    return { text: splice(text, start, end, block), start: start + block.length, end: start + block.length };
  }

  // --- smart typing -------------------------------------------------------

  // Enter inside a list: repeat the marker, or clear it if the item is empty.
  function continueList(text, pos) {
    const a = lineStart(text, pos);
    const line = text.slice(a, lineEnd(text, pos));
    const m = line.match(MARKER);
    if (!m) return null;                       // not a list; caller inserts a plain newline

    const marker = m[0];
    if (line.trim() === marker.trim()) {       // empty item -> end the list
      return { text: splice(text, a, a + marker.length, ''), start: a, end: a };
    }
    const ordered = marker.match(/^(\s*)(\d+)\.(\s+)$/);
    const next = ordered
      ? ordered[1] + (parseInt(ordered[2], 10) + 1) + '.' + ordered[3]
      : marker.replace(/\[[xX]\]/, '[ ]');     // a new task starts unchecked
    const insert = '\n' + next;
    return { text: splice(text, pos, pos, insert), start: pos + insert.length, end: pos + insert.length };
  }

  function shift(text, start, end, out) {
    const [a, b] = lineSpan(text, start, end);
    const lines = text.slice(a, b).split('\n').map(line => {
      if (out) return line.replace(/^ {1,2}/, '');
      return line.trim() === '' ? line : '  ' + line;
    }).join('\n');
    return { text: splice(text, a, b, lines), start: a, end: a + lines.length };
  }

  // --- task list toggling -------------------------------------------------

  // Flip the Nth GFM task marker ([ ] <-> [x]). The Nth checkbox in the rendered
  // DOM maps to the Nth marker in source only if we count the same set marked
  // does, so fenced code blocks (where "[ ]" is literal) are skipped. A list
  // marker and a space/end after "]" are required, so a stray "[x]" in prose
  // is not counted. Out-of-range returns the text unchanged.
  const TASK = /^(\s*(?:[-*+]|\d+\.)\s+\[)([ xX])(\](?:\s|$))/;

  function toggleTask(text, index) {
    const lines = text.split('\n');
    let count = 0, inFence = false, fence = '';

    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (inFence) {
        if (trimmed.indexOf(fence) === 0) inFence = false;
        continue;
      }
      if (trimmed.indexOf('```') === 0 || trimmed.indexOf('~~~') === 0) {
        inFence = true;
        fence = trimmed.slice(0, 3);
        continue;
      }
      const m = lines[i].match(TASK);
      if (!m) continue;
      if (count === index) {
        lines[i] = m[1] + (m[2] === ' ' ? 'x' : ' ') + m[3] + lines[i].slice(m[0].length);
        return lines.join('\n');
      }
      count++;
    }
    return text;
  }

  // --- dispatch -----------------------------------------------------------

  const OPS = {
    bold:      (t, s, e) => wrap(t, s, e, '**'),
    italic:    (t, s, e) => wrap(t, s, e, '_'),
    strike:    (t, s, e) => wrap(t, s, e, '~~'),
    code:      (t, s, e) => wrap(t, s, e, '`'),
    codeblock: codeBlock,
    link:      link,
    table:     table,
    quote:  (t, s, e) => prefixLines(t, s, e, () => '> ', QUOTE, null),
    bullet: (t, s, e) => prefixLines(t, s, e, () => '- ', /^(\s*)[-*+]\s+/, MARKER),
    number: (t, s, e) => prefixLines(t, s, e, i => (i + 1) + '. ', /^(\s*)\d+\.\s+/, MARKER),
    task:   (t, s, e) => prefixLines(t, s, e, () => '- [ ] ', /^(\s*)[-*+]\s+\[[ xX]\]\s+/, MARKER),
    heading: (t, s, e, level) => {
      const hashes = '#'.repeat(level || 1) + ' ';
      const same = new RegExp('^(\\s*)' + '#'.repeat(level || 1) + '\\s+');
      return prefixLines(t, s, e, () => hashes, same, HEADING);
    },
    indent:  (t, s, e) => shift(t, s, e, false),
    outdent: (t, s, e) => shift(t, s, e, true),
  };

  function apply(kind, text, start, end, arg) {
    const op = OPS[kind];
    if (!op) return null;
    return op(text, start, end, arg);
  }

  global.MDEdits = { apply: apply, continueList: continueList, toggleTask: toggleTask };
})(this);
