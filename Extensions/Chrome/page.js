// Runs in the page's own JavaScript world so it can see the page's media session and players.
(() => {
  if (window.__notchIsland) return;
  window.__notchIsland = true;

  // Sites whose controls need more than the generic <video>/<audio> handling.
  const SITES = [
    { host: /(^|\.)music\.youtube\.com$/, name: "YouTube Music", next: ".next-button", previous: ".previous-button" },
    { host: /(^|\.)youtube\.com$/, name: "YouTube", next: ".ytp-next-button" },
    { host: /(^|\.)netflix\.com$/, name: "Netflix", canSeek: false, title: () => document.querySelector('[data-uia="video-title"]')?.innerText },
    { host: /(^|\.)open\.spotify\.com$/, name: "Spotify", next: '[data-testid="control-button-skip-forward"]', previous: '[data-testid="control-button-skip-back"]', toggle: '[data-testid="control-button-playpause"]' },
    { host: /(^|\.)soundcloud\.com$/, name: "SoundCloud", next: ".skipControl__next", previous: ".skipControl__previous" },
    { host: /(^|\.)twitch\.tv$/, name: "Twitch", canSeek: false },
    { host: /(^|\.)primevideo\.com$/, name: "Prime Video" },
    { host: /(^|\.)disneyplus\.com$/, name: "Disney+" },
  ];
  const site = SITES.find((s) => s.host.test(location.hostname)) || {
    name: location.hostname.replace(/^www\./, ""),
  };

  // Players such as Spotify's never attach their <audio> to the page, so remember anything that plays.
  const known = new Set();
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
      canSkip: Boolean(site.next),
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
  window.addEventListener("pagehide", () => window.postMessage({ __notchIsland: "state", state: null }, location.origin));

  function click(selector) {
    const button = selector && document.querySelector(selector);
    if (button) button.click();
    return Boolean(button);
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.__notchIsland !== "command") return;
    const el = currentMedia();
    switch (event.data.action) {
      case "toggle":
        if (!click(site.toggle) && el) el.paused ? el.play() : el.pause();
        break;
      case "next":
        click(site.next);
        break;
      case "previous":
        if (!click(site.previous) && el) el.currentTime = 0;
        break;
      case "seek":
        if (el && site.canSeek !== false) el.currentTime = event.data.time;
        break;
    }
    setTimeout(() => report(true), 250);
  });
})();
