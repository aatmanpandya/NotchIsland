// Keeps one WebSocket to the NotchIsland app and forwards each tab's playback state to it.
const PORT = 47823;
const tabs = new Map(); // tabId -> latest state

const BROWSER =
  navigator.userAgentData?.brands?.map((b) => b.brand).find((b) => !/Chromium|Not.?A.?Brand/i.test(b)) ||
  "Chrome";
const shortName = BROWSER.replace(/^(Google|Microsoft) /, "");

let socket = null;
let retryTimer = null;

function connect() {
  if (socket && socket.readyState <= WebSocket.OPEN) return;
  socket = new WebSocket(`ws://127.0.0.1:${PORT}`);
  socket.onopen = sync;
  socket.onmessage = (event) => {
    try {
      const message = JSON.parse(event.data);
      if (message.type === "command") handleCommand(message);
    } catch {}
  };
  socket.onclose = () => {
    socket = null;
    clearTimeout(retryTimer);
    retryTimer = setTimeout(connect, 3000);
  };
  socket.onerror = () => {};
}

function sync() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  const list = [...tabs.entries()].map(([tabId, state]) => ({ tabId, ...state }));
  socket.send(JSON.stringify({ type: "state", browser: shortName, tabs: list }));
}

async function handleCommand({ tabId, action, time }) {
  if (action === "focus") {
    const tab = await chrome.tabs.update(tabId, { active: true }).catch(() => null);
    if (tab) await chrome.windows.update(tab.windowId, { focused: true }).catch(() => {});
    return;
  }
  chrome.tabs.sendMessage(tabId, { type: "command", action, time }).catch(() => {});
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message.type !== "state" || !sender.tab) return;
  if (message.state) tabs.set(sender.tab.id, { ...message.state, updatedAt: Date.now() });
  else tabs.delete(sender.tab.id);
  connect();
  sync();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabs.delete(tabId)) sync();
});

// Regular traffic keeps the worker alive while connected; reconnect if the app was restarted.
setInterval(() => {
  if (socket?.readyState === WebSocket.OPEN) socket.send('{"type":"ping"}');
  else connect();
}, 20000);

connect();
