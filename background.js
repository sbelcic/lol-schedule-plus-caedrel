import { DEFAULT_STREAMERS, DEFAULT_REFRESH_MIN, fetchChannels, channelUrl } from "./shared.js";

const POLL_ALARM = "live-poll";
const BADGE_BG = "#9146ff";
const DEFAULTS = { streamers: DEFAULT_STREAMERS, notifyLive: false, desktopNotify: false, refreshMinutes: DEFAULT_REFRESH_MIN };

async function settings() {
  return chrome.storage.local.get({ ...DEFAULTS, liveLogins: [], liveInit: false });
}

async function clearBadge() {
  await chrome.action.setBadgeText({ text: "" });
  await chrome.action.setTitle({ title: "LoL Schedule" });
}

async function showBadge(live) {
  if (!live.length) return clearBadge();
  await chrome.action.setBadgeText({ text: live.length === 1 ? live[0].displayName.slice(0, 4).toUpperCase() : String(live.length) });
  await chrome.action.setBadgeBackgroundColor({ color: BADGE_BG });
  if (chrome.action.setBadgeTextColor) await chrome.action.setBadgeTextColor({ color: "#ffffff" });
  const lines = live.map((c) => `${c.displayName}${c.game ? " • " + c.game : ""}`);
  await chrome.action.setTitle({ title: `Live now:\n${lines.join("\n")}` });
}

function notify(c) {
  chrome.notifications.create(`live:${c.login}`, {
    type: "basic",
    iconUrl: "icons/icon-128.png",
    title: `${c.displayName} is live`,
    message: [c.game, c.title].filter(Boolean).join(" — ") || "Just went live on Twitch"
  });
}

async function syncAlarm() {
  const s = await settings();
  const enabled = (s.notifyLive || s.desktopNotify) && s.streamers.length > 0;
  const existing = await chrome.alarms.get(POLL_ALARM);
  if (enabled && (!existing || existing.periodInMinutes !== s.refreshMinutes)) {
    chrome.alarms.create(POLL_ALARM, { periodInMinutes: s.refreshMinutes });
  }
  if (!enabled && existing) await chrome.alarms.clear(POLL_ALARM);
  return enabled;
}

// baseline=true records who is live right now without sending notifications
async function poll(baseline = false) {
  try {
    const enabled = await syncAlarm();
    const s = await settings();
    if (!enabled) {
      await chrome.storage.local.set({ liveLogins: [], liveInit: false });
      return clearBadge();
    }
    const channels = await fetchChannels(s.streamers);
    const live = Object.values(channels).filter((c) => c?.live);

    if (s.desktopNotify && s.liveInit && !baseline) {
      const before = new Set(s.liveLogins);
      live.filter((c) => !before.has(c.login)).forEach(notify);
    }
    await chrome.storage.local.set({
      liveLogins: live.map((c) => c.login),
      liveInit: true
    });

    if (s.notifyLive) await showBadge(live);
    else await clearBadge();
  } catch (e) {
    console.error("[LoL Schedule] poll failed:", e.message);
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  const cur = await chrome.storage.local.get(["streamers"]);
  if (!cur.streamers) await chrome.storage.local.set({ streamers: DEFAULT_STREAMERS });
  await syncAlarm();
  poll(true);
});

chrome.runtime.onStartup.addListener(() => poll(true));

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === POLL_ALARM) poll();
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.refreshMinutes) syncAlarm();
  if (area === "local" && (changes.streamers || changes.notifyLive || changes.desktopNotify)) {
    poll(true);
  }
});

chrome.notifications.onClicked.addListener((id) => {
  if (!id.startsWith("live:")) return;
  chrome.tabs.create({ url: channelUrl(id.slice(5)) });
  chrome.notifications.clear(id);
});
