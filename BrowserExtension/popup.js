// Popup UI for the browser extension
const dot = document.getElementById('dot');
const statusEl = document.getElementById('status');
const lastEl = document.getElementById('last');
const openBtn = document.getElementById('open-app');

let ws;

function updateStatus(connected) {
  if (connected) {
    dot.classList.remove('red');
    dot.classList.add('green');
    statusEl.textContent = 'Connected to ScanToExternApp';
  } else {
    dot.classList.remove('green');
    dot.classList.add('red');
    statusEl.textContent = 'Disconnected — open the native app';
  }
}

function connectWS() {
  try {
    ws = new WebSocket('ws://127.0.0.1:52731');
    ws.onopen = () => updateStatus(true);
    ws.onclose = () => {
      updateStatus(false);
      setTimeout(connectWS, 3000);
    };
    ws.onmessage = (ev) => {
      try {
        const m = JSON.parse(ev.data);
        if (m.type === 'scan') {
          lastEl.textContent = 'Last: ' + (m.text || '').slice(0, 80);
        }
      } catch (_) {}
    };
  } catch (e) {
    updateStatus(false);
    setTimeout(connectWS, 3000);
  }
}

openBtn.onclick = () => {
  // Custom URL scheme (for future) or just focus instruction
  window.alert('Look for the ScanToExternApp icon in your macOS menubar (or Windows tray).');
};

connectWS();
updateStatus(false);
