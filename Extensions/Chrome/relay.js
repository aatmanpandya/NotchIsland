// Passes messages between the page script and the extension's background worker.
window.addEventListener("message", (event) => {
  if (event.source !== window || event.data?.__notchIsland !== "state") return;
  try {
    chrome.runtime.sendMessage({ type: "state", state: event.data.state }).catch(() => {});
  } catch {
    // The extension was reloaded; this page's copy is orphaned until it refreshes.
  }
});

chrome.runtime.onMessage.addListener((message) => {
  if (message.type === "command") {
    window.postMessage({ __notchIsland: "command", action: message.action, time: message.time }, location.origin);
  }
});
