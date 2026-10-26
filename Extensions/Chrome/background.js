// Keeps one WebSocket to the NotchIsland app and forwards each tab's playback state to it.
const PORT = 47823;
const tabs = new Map(); // tabId -> latest media state
const calls = new Map(); // tabId -> { site, title } while a call is live

const BROWSER =
  navigator.userAgentData?.brands?.map((b) => b.brand).find((b) => !/Chromium|Not.?A.?Brand/i.test(b)) ||
  "Chrome";
const shortName = BROWSER.replace(/^(Google|Microsoft) /, "");

let socket = null;
let retryTimer = null;
// Retries slow down while the app isn't running (each failed attempt is logged by Chrome),
// and reset once connected. Playback updates from a tab also reconnect right away.
let retryDelay = 3000;
const MAX_RETRY_DELAY = 30000;

function connect() {
  if (socket && socket.readyState <= WebSocket.OPEN) return;
  socket = new WebSocket(`ws://127.0.0.1:${PORT}`);
  socket.onopen = () => {
    retryDelay = 3000;
    sync();
  };
  socket.onmessage = (event) => {
    try {
      const message = JSON.parse(event.data);
      if (message.type === "command") handleCommand(message);
    } catch {}
  };
  socket.onclose = () => {
    socket = null;
    clearTimeout(retryTimer);
    retryTimer = setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, MAX_RETRY_DELAY);
  };
  socket.onerror = () => {};
}

function sync() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  const list = [...tabs.entries()].map(([tabId, state]) => ({ tabId, ...state }));
  const callList = [...calls.entries()].map(([tabId, call]) => ({ tabId, ...call }));
  socket.send(JSON.stringify({ type: "state", browser: shortName, tabs: list, calls: callList }));
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
  if (!sender.tab) return;
  const tabId = sender.tab.id;
  if (message.type === "state") {
    if (message.state) tabs.set(tabId, { ...message.state, updatedAt: Date.now() });
    else tabs.delete(tabId);
  } else if (message.type === "call") {
    if (message.call) calls.set(tabId, message.call);
    else calls.delete(tabId);
  } else {
    return;
  }
  connect();
  sync();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  const hadMedia = tabs.delete(tabId);
  const hadCall = calls.delete(tabId);
  if (hadMedia || hadCall) sync();
});

// Regular traffic keeps the worker alive while connected. Reconnecting is left to the retry timer.
setInterval(() => {
  if (socket?.readyState === WebSocket.OPEN) socket.send('{"type":"ping"}');
}, 20000);

connect();
