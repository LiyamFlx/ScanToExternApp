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
