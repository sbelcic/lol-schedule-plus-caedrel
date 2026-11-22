import { DEFAULT_STREAMERS, MAX_STREAMERS, DEFAULT_REFRESH_MIN, REFRESH_OPTIONS, fetchChannels, parseChannel, channelUrl } from "./shared.js";

// Public lolesports.com API key (bundled in their own client JS).
const API_KEY = "0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z";
const API_URL = "https://esports-api.lolesports.com/persisted/gw/getSchedule?hl=en-US&leagueId=";

const LEAGUES_URL = "https://esports-api.lolesports.com/persisted/gw/getLeagues?hl=en-US";
const LEAGUES_TTL = 24 * 3600 * 1000;

// Used as the default selection, and as a fallback if getLeagues is unreachable.
const DEFAULT_LEAGUES = [
  { id: "98767991310872058", name: "LCK", region: "KOREA" },
  { id: "98767991302996019", name: "LEC", region: "EMEA" },
  { id: "98767991325878492", name: "MSI", region: "INTERNATIONAL" },
  { id: "98767975604431411", name: "Worlds", region: "INTERNATIONAL" },
  { id: "116838530616006090", name: "Esports World Cup", region: "INTERNATIONAL" },
  { id: "116929044967296666", name: "KeSPA Cup", region: "KOREA" },
  { id: "98767991299243165", name: "LCS", region: "NORTH AMERICA" },
  { id: "117126995932274206", name: "Demacia Cup", region: "CHINA" }
];
const DEFAULT_LEAGUE_IDS = DEFAULT_LEAGUES.map((l) => l.id);

const LEAGUE_SHORT = {
  "Mid-Season Invitational": "MSI",
  "World Championship": "Worlds",
  "Esports World Cup": "EWC",
  "KeSPA Cup": "KESPA",
  "Demacia Cup": "DEMACIA"
};

const $ = (s) => document.querySelector(s);
const el = {
  content: $("#content"), updated: $("#updated"), filters: $("#filters"), liveStrip: $("#liveStrip"),
  refreshBtn: $("#refreshBtn"), settingsBtn: $("#settingsBtn"), backBtn: $("#backBtn"),
  scheduleView: $("#scheduleView"), settingsView: $("#settingsView"),
  badgeSwitch: $("#badgeSwitch"), notifySwitch: $("#notifySwitch"),
  input: $("#streamerInput"), addBtn: $("#addBtn"), msg: $("#streamerMsg"),
  list: $("#streamerList"), count: $("#streamerCount"),
  interval: $("#intervalSelect"), footer: $("#footerNote"),
  leagueList: $("#leagueList"), leagueSearch: $("#leagueSearch"), leagueCount: $("#leagueCount"),
  leagueReset: $("#leagueReset"), leagueClear: $("#leagueClear")
};

const state = { events: [], channels: {}, streamers: [], filter: "ALL", refreshMin: DEFAULT_REFRESH_MIN, leagues: [], selected: new Set(DEFAULT_LEAGUE_IDS) };
let timer = null;
let refetchTimer = null;

const escapeHtml = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const leagueShort = (ev) => LEAGUE_SHORT[ev.league?.name] || ev.league?.name || "";

/* ---------- schedule ---------- */

async function fetchSchedule(ids) {
  if (!ids.length) return [];
  const results = await Promise.allSettled(
    ids.map(async (id) => {
      const r = await fetch(API_URL + id, { headers: { "x-api-key": API_KEY } });
      if (!r.ok) throw new Error("HTTP " + r.status);
      const j = await r.json();
      return (j?.data?.schedule?.events || []).map((e) => ({ ...e, leagueId: id }));
    })
  );
  const ok = results.filter((r) => r.status === "fulfilled");
  if (!ok.length) throw results[0].reason;
  return ok.flatMap((r) => r.value).filter((e) => e.type === "match");
}

async function loadLeagues() {
  const { leaguesCache } = await chrome.storage.local.get({ leaguesCache: null });
  if (leaguesCache?.list?.length && Date.now() - leaguesCache.t < LEAGUES_TTL) {
    state.leagues = leaguesCache.list;
    return;
  }
  try {
    const r = await fetch(LEAGUES_URL, { headers: { "x-api-key": API_KEY } });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const j = await r.json();
    const list = (j?.data?.leagues || [])
      .filter((l) => l.id && l.name)
      .map((l) => ({ id: String(l.id), name: l.name, region: l.region || "" }));
    if (!list.length) throw new Error("empty");
    state.leagues = list;
    chrome.storage.local.set({ leaguesCache: { t: Date.now(), list } }).catch(() => {});
  } catch {
    state.leagues = leaguesCache?.list?.length ? leaguesCache.list : DEFAULT_LEAGUES;
  }
}

function fmtTimeParts(d) {
  const s = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  const m = s.match(/(\d+:\d+)\s*([AP]M)?/i);
  return m ? { h: m[1], ap: m[2] || "" } : { h: s, ap: "" };
}

function dayBucket(d, now) {
  const today = new Date(now); today.setHours(0, 0, 0, 0);
  const target = new Date(d); target.setHours(0, 0, 0, 0);
  const diff = Math.round((target - today) / 86400000);
  if (diff < 0) return null;
  if (diff === 0) return "Later today";
  if (diff === 1) return "Tomorrow";
  if (diff < 7) return d.toLocaleDateString([], { weekday: "long" });
  return d.toLocaleDateString([], { month: "short", day: "numeric" });
}

function liveHref(ev) {
  const live = Object.values(state.channels).find((c) => c?.live);
  if (live) return channelUrl(live.login);
  return `https://lolesports.com/en-GB/live/${encodeURIComponent(ev.league?.slug || "")}`;
}

function renderMatch(ev) {
  const m = ev.match || {};
  const [t1 = {}, t2 = {}] = m.teams || [];
  const { h, ap } = fmtTimeParts(new Date(ev.startTime));
  const isLive = ev.state === "inProgress";
  const isDone = ev.state === "completed";
  const bo = m.strategy ? `Bo${m.strategy.count}` : "";
  const week = escapeHtml(ev.blockName || "");
  const league = escapeHtml(leagueShort(ev));
  const w1 = t1.result?.outcome === "win";
  const w2 = t2.result?.outcome === "win";
  const cls1 = isDone ? (w1 ? "winner" : "loser") : "";
  const cls2 = isDone ? (w2 ? "winner" : "loser") : "";
  const score = isDone
    ? `<span class="score"><span class="${w1 ? "w" : ""}">${t1.result?.gameWins ?? ""}</span>:<span class="${w2 ? "w" : ""}">${t2.result?.gameWins ?? ""}</span></span>`
    : bo;

  const open = isLive
    ? `<a class="match match-live" href="${escapeHtml(liveHref(ev))}" target="_blank" rel="noopener" title="Watch live">`
    : `<div class="match">`;

  return `${open}
    <div class="row">
      <div class="time"><span class="h">${escapeHtml(h)}</span><span class="ap">${escapeHtml(ap)}</span></div>
      <div class="teams">
        <div class="team left ${cls1}">
          <span class="code">${escapeHtml(t1.code || "TBD")}</span>
          ${t1.image ? `<img src="${escapeHtml(t1.image)}" alt="" loading="lazy">` : ""}
        </div>
        <div class="vs">/</div>
        <div class="team right ${cls2}">
          ${t2.image ? `<img src="${escapeHtml(t2.image)}" alt="" loading="lazy">` : ""}
          <span class="code">${escapeHtml(t2.code || "TBD")}</span>
        </div>
      </div>
    </div>
    <div class="foot">
      <span class="league-badge">${league}</span>
      <span class="center">${week}${isLive ? `${week ? " · " : ""}<span class="live-text">LIVE</span>` : ""}</span>
      <span class="right">${score}</span>
    </div>
  ${isLive ? "</a>" : "</div>"}`;
}

function renderSchedule() {
  const now = new Date();
  const cutoff = now.getTime() - 3 * 3600 * 1000;
  let live = [], upcoming = [];
  if (!state.selected.size) {
    el.filters.innerHTML = "";
    el.content.innerHTML = `<div class="empty">No leagues selected. Open Settings (⚙) to choose some.</div>`;
    return;
  }
  const visible = state.events.filter((e) => !e.leagueId || state.selected.has(e.leagueId));
  for (const e of visible) {
    if (e.state === "inProgress") live.push(e);
    else if (e.state === "unstarted" && new Date(e.startTime).getTime() >= cutoff) upcoming.push(e);
  }

  // league filter chips
  const leagues = [...new Set([...live, ...upcoming].map(leagueShort))].filter(Boolean).sort();
  if (state.filter !== "ALL" && !leagues.includes(state.filter)) state.filter = "ALL";
  el.filters.innerHTML = leagues.length > 1
    ? ["ALL", ...leagues].map((l) =>
        `<button class="chip" data-league="${escapeHtml(l)}" aria-pressed="${l === state.filter}">${l === "ALL" ? "All" : escapeHtml(l)}</button>`
      ).join("")
    : "";
  if (state.filter !== "ALL") {
    live = live.filter((e) => leagueShort(e) === state.filter);
    upcoming = upcoming.filter((e) => leagueShort(e) === state.filter);
  }

  const byTime = (a, b) => new Date(a.startTime) - new Date(b.startTime) || (a.league?.name || "").localeCompare(b.league?.name || "");
  live.sort(byTime);
  upcoming.sort(byTime);

  const groups = new Map();
  if (live.length) groups.set("Live", live);
  for (const e of upcoming) {
    const b = dayBucket(new Date(e.startTime), now);
    if (!b) continue;
    if (!groups.has(b)) groups.set(b, []);
    groups.get(b).push(e);
  }

  if (!groups.size) {
    el.content.innerHTML = `<div class="empty">No upcoming matches.</div>`;
    return;
  }
  let html = "";
  for (const [name, list] of groups) {
    html += `<div class="section"><h2>${escapeHtml(name)}${name === "Live" ? '<span class="badge">LIVE</span>' : ""}</h2>`;
    html += list.map(renderMatch).join("") + `</div>`;
  }
  el.content.innerHTML = html;
}

function setUpdated() {
  el.updated.textContent = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

async function refreshSchedule() {
  el.refreshBtn.classList.add("spin");
  try {
    state.events = await fetchSchedule([...state.selected]);
    renderSchedule();
    setUpdated();
    chrome.storage.local.set({ scheduleCache: state.events }).catch(() => {});
  } catch (e) {
    const err = `<div class="error">Couldn't load the schedule (${escapeHtml(e.message)}). Check your connection and try again.</div>`;
    if (state.events.length) {
      renderSchedule();
      el.content.insertAdjacentHTML("afterbegin", err);
    } else {
      el.content.innerHTML = err;
    }
  } finally {
    el.refreshBtn.classList.remove("spin");
  }
}

/* ---------- streamers ---------- */

function renderLiveStrip() {
  const live = state.streamers.map((l) => state.channels[l]).filter((c) => c?.live);
  el.liveStrip.hidden = !live.length;
  el.liveStrip.innerHTML = live.map((c) => `
    <a class="live-chip" href="${channelUrl(c.login)}" target="_blank" rel="noopener"
       title="${escapeHtml(c.title)}">
      <img class="avatar" src="${escapeHtml(c.avatar)}" alt="">
      <span>${escapeHtml(c.displayName)}</span>
      <span class="viewers">${c.viewers.toLocaleString()}</span>
    </a>`).join("");
}

function renderStreamerList() {
  el.count.textContent = `${state.streamers.length}/${MAX_STREAMERS}`;
  el.list.innerHTML = state.streamers.map((login) => {
    const c = state.channels[login];
    const name = c?.displayName || login;
    const status = c ? (c.live ? `Live${c.game ? " · " + c.game : ""}` : "Offline") : "Checking…";
    return `<li>
      ${c?.avatar ? `<img class="avatar" src="${escapeHtml(c.avatar)}" alt="">` : `<span class="avatar"></span>`}
      <span class="name"><a href="${channelUrl(login)}" target="_blank" rel="noopener">${escapeHtml(name)}</a>
        <small>${escapeHtml(status)}</small></span>
      ${c?.live ? '<span class="dot" title="Live"></span>' : ""}
      <button class="remove" data-login="${escapeHtml(login)}" aria-label="Remove ${escapeHtml(name)}" title="Remove">×</button>
    </li>`;
  }).join("") || `<li><span class="name"><small>No streamers yet. Add a Twitch channel above.</small></span></li>`;
}

async function refreshChannels() {
  try {
    state.channels = await fetchChannels(state.streamers);
  } catch { /* keep previous state */ }
  renderLiveStrip();
  renderStreamerList();
  renderSchedule();
}

function setMsg(text, ok = false) {
  el.msg.textContent = text;
  el.msg.classList.toggle("ok", ok);
}

async function addStreamer() {
  const login = parseChannel(el.input.value);
  if (!login) return setMsg("Enter a Twitch channel name or URL, like twitch.tv/caedrel.");
  if (state.streamers.includes(login)) return setMsg("That streamer is already in your list.");
  if (state.streamers.length >= MAX_STREAMERS) return setMsg(`You can track up to ${MAX_STREAMERS} streamers.`);

  el.addBtn.disabled = true;
  try {
    const map = await fetchChannels([login]);
    if (!map[login]) return setMsg("Channel not found on Twitch.");
    state.streamers.push(login);
    state.channels[login] = map[login];
    await chrome.storage.local.set({ streamers: state.streamers });
    el.input.value = "";
    setMsg(`Added ${map[login].displayName}.`, true);
    renderLiveStrip();
    renderStreamerList();
  } catch {
    setMsg("Couldn't reach Twitch. Try again in a moment.");
  } finally {
    el.addBtn.disabled = false;
  }
}

async function removeStreamer(login) {
  state.streamers = state.streamers.filter((l) => l !== login);
  delete state.channels[login];
  await chrome.storage.local.set({ streamers: state.streamers });
  setMsg("");
  renderLiveStrip();
  renderStreamerList();
}

/* ---------- settings ---------- */

function setSwitch(btn, on) { btn.setAttribute("aria-checked", String(!!on)); }

async function toggleSetting(key, btn) {
  const cur = await chrome.storage.local.get({ [key]: false });
  const next = !cur[key];
  if (key === "desktopNotify" && next) {
    // make sure the first poll after enabling doesn't notify for streamers already live
    await chrome.storage.local.set({ liveInit: false });
  }
  await chrome.storage.local.set({ [key]: next });
  setSwitch(btn, next);
}

function startTimer() {
  clearInterval(timer);
  timer = setInterval(() => { refreshSchedule(); refreshChannels(); }, state.refreshMin * 60000);
  el.footer.textContent = `Auto-refresh every ${state.refreshMin} min`;
}

function renderLeagueList() {
  const q = el.leagueSearch.value.trim().toLowerCase();
  const items = state.leagues
    .filter((l) => !q || `${l.name} ${l.region}`.toLowerCase().includes(q))
    .sort((a, b) => Number(state.selected.has(b.id)) - Number(state.selected.has(a.id)) || a.name.localeCompare(b.name));
  el.leagueList.innerHTML = items.map((l) => `
    <li><label>
      <input type="checkbox" data-id="${escapeHtml(l.id)}"${state.selected.has(l.id) ? " checked" : ""}>
      <span class="lname">${escapeHtml(l.name)}</span>
      <small>${escapeHtml(l.region)}</small>
    </label></li>`).join("") || `<li class="none">No leagues match your search.</li>`;
  el.leagueCount.textContent = `${state.selected.size} selected`;
}

function saveLeagues() {
  el.leagueCount.textContent = `${state.selected.size} selected`;
  chrome.storage.local.set({ selectedLeagues: [...state.selected] }).catch(() => {});
  renderSchedule();
  clearTimeout(refetchTimer);
  refetchTimer = setTimeout(refreshSchedule, 600);
}

function showSettings(show) {
  el.scheduleView.hidden = show;
  el.settingsView.hidden = !show;
  el.settingsBtn.classList.toggle("on", show);
  if (show) el.input.focus();
}

/* ---------- events ---------- */

// let the mouse wheel scroll the live strip sideways
el.liveStrip.addEventListener("wheel", (e) => {
  if (e.deltaY && el.liveStrip.scrollWidth > el.liveStrip.clientWidth) {
    e.preventDefault();
    el.liveStrip.scrollLeft += e.deltaY;
  }
}, { passive: false });

el.settingsBtn.addEventListener("click", () => showSettings(el.settingsView.hidden));
el.backBtn.addEventListener("click", () => showSettings(false));
el.refreshBtn.addEventListener("click", () => { refreshSchedule(); refreshChannels(); });
el.badgeSwitch.addEventListener("click", () => toggleSetting("notifyLive", el.badgeSwitch));
el.notifySwitch.addEventListener("click", () => toggleSetting("desktopNotify", el.notifySwitch));
el.interval.addEventListener("change", async () => {
  state.refreshMin = Number(el.interval.value);
  await chrome.storage.local.set({ refreshMinutes: state.refreshMin });
  startTimer();
});
el.leagueSearch.addEventListener("input", renderLeagueList);
el.leagueList.addEventListener("change", (e) => {
  const cb = e.target.closest("input[data-id]");
  if (!cb) return;
  if (cb.checked) state.selected.add(cb.dataset.id);
  else state.selected.delete(cb.dataset.id);
  saveLeagues();
});
el.leagueReset.addEventListener("click", () => {
  state.selected = new Set(DEFAULT_LEAGUE_IDS);
  renderLeagueList();
  saveLeagues();
});
el.leagueClear.addEventListener("click", () => {
  state.selected = new Set();
  renderLeagueList();
  saveLeagues();
});
el.addBtn.addEventListener("click", addStreamer);
el.input.addEventListener("keydown", (e) => { if (e.key === "Enter") addStreamer(); });
el.list.addEventListener("click", (e) => {
  const b = e.target.closest(".remove");
  if (b) removeStreamer(b.dataset.login);
});
el.filters.addEventListener("click", (e) => {
  const b = e.target.closest(".chip");
  if (!b) return;
  state.filter = b.dataset.league;
  chrome.storage.local.set({ leagueFilter: state.filter }).catch(() => {});
  renderSchedule();
});

/* ---------- init ---------- */

async function init() {
  const s = await chrome.storage.local.get({
    streamers: DEFAULT_STREAMERS, notifyLive: false, desktopNotify: false,
    scheduleCache: [], leagueFilter: "ALL", refreshMinutes: DEFAULT_REFRESH_MIN,
    selectedLeagues: DEFAULT_LEAGUE_IDS
  });
  state.streamers = s.streamers;
  state.filter = s.leagueFilter;
  state.events = s.scheduleCache;
  state.selected = new Set(s.selectedLeagues);
  state.refreshMin = REFRESH_OPTIONS.includes(s.refreshMinutes) ? s.refreshMinutes : DEFAULT_REFRESH_MIN;
  el.interval.innerHTML = REFRESH_OPTIONS.map((m) =>
    `<option value="${m}"${m === state.refreshMin ? " selected" : ""}>${m} min</option>`).join("");
  setSwitch(el.badgeSwitch, s.notifyLive);
  setSwitch(el.notifySwitch, s.desktopNotify);

  if (state.events.length) renderSchedule(); // instant paint from cache
  else el.content.innerHTML = `<div class="empty">Loading…</div>`;
  renderStreamerList();
  loadLeagues().then(renderLeagueList);

  await Promise.all([refreshSchedule(), refreshChannels()]);
  startTimer();
}

init();
