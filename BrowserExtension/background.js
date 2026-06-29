// ScanToExternApp Browser Extension — background service worker (MV3)
// Connects to native app WebSocket on 127.0.0.1:52731
// Forwards 'scan' messages to the active tab's content script.

let socket = null;
let reconnectTimer = null;

function connect() {
  if (socket && socket.readyState === WebSocket.OPEN) return;

  socket = new WebSocket('ws://127.0.0.1:52731');

  socket.onopen = () => {
    console.log('[ScanToExternApp Ext] Connected to native app WS');
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
  };

  socket.onmessage = async (event) => {
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch (e) {
      return;
    }

    if (msg.type === 'scan' && msg.text) {
      // Find active tab and forward
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tab && tab.id != null) {
        chrome.tabs.sendMessage(tab.id, { type: 'inject', text: msg.text, id: msg.id });
      }
      // ACK back
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: 'ack', id: msg.id }));
      }
    }
  };

  socket.onclose = () => {
    console.log('[ScanToExternApp Ext] WS closed, will reconnect');
    reconnectTimer = setTimeout(connect, 2500);
  };

  socket.onerror = () => {
    if (socket) socket.close();
  };
}

connect();

// Optional: keepalive ping every 25s
setInterval(() => {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ type: 'ping' }));
  }
}, 25000);

// MV3 reliability: the service worker is terminated after ~30s idle, which would drop the
// WebSocket and stop scans from arriving. chrome.alarms wakes the worker on a schedule; each
// wake re-establishes the socket if it was lost. This keeps the bridge alive long-term.
chrome.alarms.create('ws-keepalive', { periodInMinutes: 0.4 }); // ~24s
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === 'ws-keepalive') {
    if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
      connect();
    } else if (socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ type: 'ping' }));
    }
  }
});

// Reconnect promptly when the worker (re)starts or the browser wakes.
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
