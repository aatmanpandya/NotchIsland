// Runs in the page's own JavaScript world so it can see the page's media session and players.
(() => {
  if (window.__notchIsland) return;
  window.__notchIsland = true;

  // Sites whose controls need more than the generic <video>/<audio> handling.
  const SITES = [
    { host: /(^|\.)music\.youtube\.com$/, name: "YouTube Music", next: ".next-button", previous: ".previous-button", music: true },
    { host: /(^|\.)youtube\.com$/, name: "YouTube", next: ".ytp-next-button", previous: ".ytp-prev-button", historyBack: true },
    { host: /(^|\.)netflix\.com$/, name: "Netflix", canSeek: false, title: () => document.querySelector('[data-uia="video-title"]')?.innerText },
    { host: /(^|\.)open\.spotify\.com$/, name: "Spotify", next: '[data-testid="control-button-skip-forward"]', previous: '[data-testid="control-button-skip-back"]', toggle: '[data-testid="control-button-playpause"]', music: true },
    { host: /(^|\.)soundcloud\.com$/, name: "SoundCloud", next: ".skipControl__next", previous: ".skipControl__previous", music: true },
    { host: /(^|\.)twitch\.tv$/, name: "Twitch", canSeek: false },
    { host: /(^|\.)primevideo\.com$/, name: "Prime Video" },
    { host: /(^|\.)disneyplus\.com$/, name: "Disney+" },
    { host: /(^|\.)meet\.google\.com$/, name: "Google Meet" },
    { host: /(^|\.)zoom\.us$/, name: "Zoom" },
    { host: /(^|\.)teams\.(microsoft|live)\.com$/, name: "Microsoft Teams" },
    { host: /(^|\.)discord\.com$/, name: "Discord" },
    { host: /(^|\.)slack\.com$/, name: "Slack" },
  ];
  const site = SITES.find((s) => s.host.test(location.hostname)) || {
    name: location.hostname.replace(/^www\./, ""),
  };

  // Players such as Spotify's never attach their <audio> to the page, so remember anything that plays.
  const known = new Set();
  // Record the page's own media-key handlers ("nexttrack", "previoustrack", ...) as it sets them.
  // Calling these is exactly what the keyboard's media keys do, so it works on any site that
  // supports them, without relying on finding the right on-screen button.
  const actions = new Map();
  if (navigator.mediaSession?.setActionHandler) {
    const originalSetActionHandler = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
    navigator.mediaSession.setActionHandler = (action, handler) => {
      if (handler) actions.set(action, handler);
      else actions.delete(action);
      return originalSetActionHandler(action, handler);
    };
  }
  function runAction(action) {
    const handler = actions.get(action);
    if (!handler) return false;
    try {
      handler({ action });
      return true;
    } catch {
      return false;
    }
  }

  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) {
    track(this);
    return originalPlay.apply(this, args);
  };

  const EVENTS = ["play", "pause", "ended", "seeked", "durationchange", "loadedmetadata", "emptied"];
  function track(el) {
    if (known.has(el)) return;
    known.add(el);
    EVENTS.forEach((type) => el.addEventListener(type, () => report(true)));
  }

  // Muted and very short clips are previews, GIFs and ads, not something the user is watching.
  // Live call streams (Meet, Zoom, Teams, Discord, webcam previews) aren't media playback either.
  function isReal(el) {
    if (el.srcObject instanceof MediaStream) return false;
    return !el.muted && el.volume > 0 && (!isFinite(el.duration) || el.duration >= 10);
  }

  function currentMedia() {
    document.querySelectorAll("video, audio").forEach(track);
    const all = [...known].filter((el) => el.isConnected || !el.paused || el.currentTime > 0).filter(isReal);
    return all.find((el) => !el.paused && !el.ended) || all.find((el) => el.currentTime > 0) || null;
  }

  function largestArtwork(md) {
    const art = [...(md?.artwork || [])];
    if (!art.length) return null;
    const area = (a) => (a.sizes || "0x0").split("x").reduce((w, h) => Number(w) * Number(h)) || 0;
    art.sort((a, b) => area(b) - area(a));
    return new URL(art[0].src, location.href).href;
  }

  function state() {
    const el = currentMedia();
    if (!el) return null;
    const md = navigator.mediaSession?.metadata;
    const duration = isFinite(el.duration) ? el.duration : 0;
    return {
      title: md?.title || site.title?.() || document.title || site.name,
      artist: md?.artist || site.name,
      album: md?.album || "",
      artwork: largestArtwork(md),
      duration,
      position: el.currentTime,
      playing: !el.paused && !el.ended,
      site: site.name,
      canSeek: site.canSeek !== false && duration > 0,
      canSkip: actions.has("nexttrack") || Boolean(site.next && document.querySelector(site.next)),
    };
  }

  // Send on every real change, plus a heartbeat while playing so the app's progress stays in sync.
  let lastKey = "";
  let lastSent = 0;
  function report(force = false) {
    const s = state();
    const { position, ...rest } = s || {};
    const key = JSON.stringify(s ? rest : null);
    const heartbeat = s?.playing && Date.now() - lastSent > 5000;
    if (!force && key === lastKey && !heartbeat) return;
    lastKey = key;
    lastSent = Date.now();
    window.postMessage({ __notchIsland: "state", state: s }, location.origin);
  }
  setInterval(report, 1000);
  window.addEventListener("pagehide", () => {
    window.postMessage({ __notchIsland: "state", state: null }, location.origin);
    window.postMessage({ __notchIsland: "call", call: null }, location.origin);
  });

  // A call is live once the page plays someone's audio from a live stream. A camera preview
  // before joining has no remote audio, so it doesn't count.
  function inCall() {
    const elements = new Set([...document.querySelectorAll("audio, video"), ...known]);
    return [...elements].some(
      (el) =>
        el.srcObject instanceof MediaStream &&
        !el.paused &&
        el.srcObject.getAudioTracks().some((track) => track.readyState === "live")
    );
  }

  // Calls are reported apart from media, so a video keeps playing in the island during a call.
  // Resent now and then so the extension recovers it if its background worker restarts.
  let wasInCall = false;
  let lastCallSent = 0;
  setInterval(() => {
    const active = inCall();
    if (active === wasInCall && !(active && Date.now() - lastCallSent > 10000)) return;
    wasInCall = active;
    lastCallSent = Date.now();
    const call = active ? { site: site.name, title: document.title } : null;
    window.postMessage({ __notchIsland: "call", call }, location.origin);
  }, 1000);

  function click(selector) {
    const button = selector && document.querySelector(selector);
    if (button) button.click();
    return Boolean(button);
  }

  // YouTube has no "previous video" outside playlists, so remember the videos watched in this
  // tab (kept in the tab's session storage, which survives YouTube's page loads).
  const WATCHED_KEY = "__notchIslandWatched";
  function videoID() {
    return new URLSearchParams(location.search).get("v");
  }
  function watched() {
    try {
      return JSON.parse(sessionStorage.getItem(WATCHED_KEY) || "[]");
    } catch {
      return [];
    }
  }
  function rememberVideo() {
    const id = videoID();
    if (!site.historyBack || !id) return;
    const list = watched();
    if (list[list.length - 1] === id) return;
    list.push(id);
    sessionStorage.setItem(WATCHED_KEY, JSON.stringify(list.slice(-50)));
  }
  window.addEventListener("yt-navigate-finish", rememberVideo);
  setInterval(rememberVideo, 1000);

  // Goes to the video watched before this one in this tab; false if there isn't one.
  function previousVideo() {
    const current = videoID();
    const list = watched();
    while (list.length && list[list.length - 1] === current) list.pop();
    const previous = list.pop();
    if (!previous) return false;
    // Drop it too: it's added back once it loads, so pressing again keeps going back.
    sessionStorage.setItem(WATCHED_KEY, JSON.stringify(list));
    location.assign(`/watch?v=${encodeURIComponent(previous)}`);
    return true;
  }

  // Music sites: past the first few seconds, "previous" restarts the song, like a music app.
  // YouTube: the previous video (in a playlist, YouTube's own previous; else the last one watched).
  function previous(el) {
    if (site.music && el && el.currentTime > 3 && site.name !== "Spotify") {
      el.currentTime = 0;
      return;
    }
    const inPlaylist = new URLSearchParams(location.search).has("list");
    if (site.historyBack && !inPlaylist) {
      if (!previousVideo() && el) el.currentTime = 0;
      return;
    }
    if (!runAction("previoustrack") && !click(site.previous) && el) el.currentTime = 0;
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.__notchIsland !== "command") return;
    const el = currentMedia();
    switch (event.data.action) {
      case "toggle":
        if (!click(site.toggle) && el) el.paused ? el.play() : el.pause();
        break;
      case "next":
        if (!runAction("nexttrack")) click(site.next);
        break;
      case "previous":
        previous(el);
        break;
      case "seek":
        if (el && site.canSeek !== false) el.currentTime = event.data.time;
        break;
    }
    setTimeout(() => report(true), 250);
  });
})();
