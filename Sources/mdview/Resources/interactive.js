// Interactive preview behaviors. `bridge` is the WKScriptMessageHandler in Swift.
// Loaded by the app template and exercised directly by check-interactive.swift.
(function () {
  const send = m => window.webkit.messageHandlers.bridge.postMessage(m);

  // Checkable task boxes: enable each, and on change flip the matching source
  // line by its document-order index.
  document.querySelectorAll('input[type=checkbox]').forEach((box, i) => {
    box.disabled = false;
    box.addEventListener('change', () => send({ kind: 'toggle', index: i }));
  });

  // Copy button on every code block (routed through Swift; navigator.clipboard
  // is unavailable in this non-secure file:// context).
  document.querySelectorAll('pre').forEach(pre => {
    const code = pre.querySelector('code');
    if (!code) return;
    const text = code.innerText;
    const btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', () => {
      send({ kind: 'copy', text });
      btn.textContent = 'Copied';
      setTimeout(() => { btn.textContent = 'Copy'; }, 1200);
    });
    pre.appendChild(btn);
  });

  // Sandboxed builds can't read files next to the document until the user grants
  // the folder. Say so only if a local image actually failed — no upfront prompt.
  function offerFolderAccess() {
    if (document.getElementById('grant-bar')) return;
    const bar = document.createElement('div');
    bar.id = 'grant-bar';
    bar.innerHTML = '<span>Images in this folder can’t be shown yet.</span>';
    const btn = document.createElement('button');
    btn.textContent = 'Show local images…';
    btn.addEventListener('click', () => send({ kind: 'grantAccess' }));
    bar.appendChild(btn);
    document.body.appendChild(bar);
  }

  document.querySelectorAll('img').forEach(img => {
    if (!img.src.startsWith('mdres:')) return;
    // may have already failed before this script ran
    if (img.complete && img.naturalWidth === 0) offerFolderAccess();
    img.addEventListener('error', offerFolderAccess);
  });
})();
