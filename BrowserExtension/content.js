// ScanToExternApp content script
// Receives 'inject' messages from background (originating from native app WS)
// Handles multiple strategies for text insertion in web pages.

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type !== 'inject' || !msg.text) return;

  const el = document.activeElement;
  if (!el) return;

  // 1. Classic input / textarea
  if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
    const start = el.selectionStart ?? el.value.length;
    const end = el.selectionEnd ?? el.value.length;
    el.value = el.value.slice(0, start) + msg.text + el.value.slice(end);
    el.selectionStart = el.selectionEnd = start + msg.text.length;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return;
  }

  // 2. contenteditable (Notion, Gmail compose, many rich editors)
  if (el.isContentEditable || (el.closest && el.closest('[contenteditable]'))) {
    document.execCommand('insertText', false, msg.text);
    return;
  }

  // 3. Google Docs specific workaround (hidden iframe)
  const gdocs = document.querySelector('.docs-texteventtarget-iframe');
  if (gdocs && gdocs.contentDocument) {
    gdocs.contentDocument.execCommand('insertText', false, msg.text);
    return;
  }

  // 4. Last resort: clipboard + exec paste (may be blocked by some sites)
  navigator.clipboard.writeText(msg.text).then(() => {
    document.execCommand('paste');
  }).catch(() => {
    // Silent fail — user can still manually paste
    console.warn('[ScanToExternApp Ext] Clipboard injection fallback failed');
  });
});
