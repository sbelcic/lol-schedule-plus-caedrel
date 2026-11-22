// Shared helpers used by both the popup and the background service worker.

// Public Twitch web client-id (used by twitch.tv itself).
const TWITCH_CLIENT_ID = "kimne78kx3ncx6brgo4mv6wki5h1ko";
const TWITCH_GQL_URL = "https://gql.twitch.tv/gql";

export const DEFAULT_STREAMERS = ["caedrel"];
export const MAX_STREAMERS = 15;
export const DEFAULT_REFRESH_MIN = 3;
export const REFRESH_OPTIONS = [1, 2, 3, 5, 10, 15]; // minutes

const RESERVED = new Set([
  "directory", "videos", "settings", "downloads", "login", "signup",
  "jobs", "turbo", "p", "search", "wallet", "friends", "subscriptions",
  "inventory", "drops", "moderator", "popout", "embed", "u", "store"
]);

const QUERY = `query($login: String!) {
  user(login: $login) {
    login displayName profileImageURL(width: 70)
    stream { id title viewersCount game { name } }
  }
}`;

/**
 * Accepts "caedrel", "@caedrel", "twitch.tv/caedrel" or a full URL.
 * Returns a lowercase login, or null if the input isn't a valid channel.
 */
export function parseChannel(input) {
  let v = String(input ?? "").trim().toLowerCase().replace(/^@/, "");
  if (!v) return null;
  if (/[./]/.test(v)) {
    try {
      const u = new URL(/^https?:\/\//.test(v) ? v : "https://" + v);
      if (!/(^|\.)twitch\.tv$/.test(u.hostname)) return null;
      v = u.pathname.split("/").filter(Boolean)[0] || "";
    } catch {
      return null;
    }
  }
  return /^[a-z0-9_]{1,25}$/.test(v) && !RESERVED.has(v) ? v : null;
}

/**
 * Fetches profile + live state for many channels in one batched request.
 * Returns { [login]: {login, displayName, avatar, live, title, game, viewers} | null }
 * (null = channel doesn't exist).
 */
export async function fetchChannels(logins) {
  if (!logins.length) return {};
  const r = await fetch(TWITCH_GQL_URL, {
    method: "POST",
    headers: { "Client-ID": TWITCH_CLIENT_ID, "Content-Type": "application/json" },
    body: JSON.stringify(logins.map((login) => ({ query: QUERY, variables: { login } })))
  });
  if (!r.ok) throw new Error("Twitch HTTP " + r.status);
  const json = await r.json();
  const out = {};
  logins.forEach((login, i) => {
    const u = json?.[i]?.data?.user;
    out[login] = u
      ? {
          login: u.login || login,
          displayName: u.displayName || login,
          avatar: u.profileImageURL || "",
          live: !!u.stream,
          title: u.stream?.title || "",
          game: u.stream?.game?.name || "",
          viewers: u.stream?.viewersCount ?? 0
        }
      : null;
  });
  return out;
}

export const channelUrl = (login) => `https://www.twitch.tv/${encodeURIComponent(login)}`;
