// Shared bits for every hub page: theme, user chip, toasts, live events.

const THEME_KEY = "test-hub-theme";

export const ICONS = {
  logo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3 8-8"/><path d="M20 12v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9"/></svg>',
  sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  moon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>',
  logout: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5M21 12H9"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>',
  doc: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h5"/></svg>',
  list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>',
  clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h16"/></svg>',
  back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>',
  pass: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>',
  fail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>',
  blocked: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/></svg>',
  skip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 5l7 7-7 7M13 5l7 7-7 7"/></svg>',
  report: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 17v-6M13 17V7M17 17v-3M4 21h16"/></svg>',
  keyboard: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10"/></svg>',
  copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>',
  expand: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 15l5 5 5-5M7 9l5-5 5 5"/></svg>',
};

export function esc(v) {
  return String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

export function initials(name) {
  return String(name || "?")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0].toUpperCase())
    .join("");
}

// Stable color per user id.
export function userColor(id) {
  let h = 0;
  for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return `hsl(${h % 360} 62% 52%)`;
}

export function avatar(user) {
  return `<span class="avatar" style="background:${userColor(user.id)}" title="${esc(user.name)}">${esc(initials(user.name))}</span>`;
}

export function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  const btn = document.getElementById("theme");
  if (btn) {
    btn.innerHTML = theme === "dark" ? ICONS.sun : ICONS.moon;
    btn.title = theme === "dark" ? "Mode terang" : "Mode gelap";
  }
}

export function toggleTheme() {
  const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  try {
    localStorage.setItem(THEME_KEY, next);
  } catch {}
  applyTheme(next);
}

export function toast(text, tone = "") {
  let box = document.querySelector(".toasts");
  if (!box) {
    box = document.createElement("div");
    box.className = "toasts";
    box.setAttribute("role", "status");
    document.body.appendChild(box);
  }
  const el = document.createElement("div");
  el.className = `toast ${tone}`;
  el.textContent = text;
  box.appendChild(el);
  setTimeout(() => el.remove(), 2600);
}

export async function api(path, opts = {}) {
  const res = await fetch(path, {
    cache: "no-store",
    ...opts,
    headers: { ...(opts.body ? { "content-type": "application/json" } : {}), ...(opts.headers || {}) },
  });
  if (res.status === 401) {
    location.href = `/login?next=${encodeURIComponent(location.pathname + location.search)}`;
    throw new Error("login required");
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.error || `HTTP ${res.status}`), { status: res.status });
  return data;
}

export function fmtTime(iso, tz, withDate = true) {
  if (!iso) return "";
  try {
    return new Intl.DateTimeFormat("id-ID", withDate ? { dateStyle: "medium", timeStyle: "short", timeZone: tz } : { timeStyle: "short", timeZone: tz }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export function relTime(iso) {
  if (!iso) return "";
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 45) return "baru saja";
  if (s < 3600) return `${Math.round(s / 60)} menit lalu`;
  if (s < 86400) return `${Math.round(s / 3600)} jam lalu`;
  return `${Math.round(s / 86400)} hari lalu`;
}

export function mountTopbar(me, { extra = "" } = {}) {
  const bar = document.getElementById("topbar");
  bar.innerHTML = `
    <div class="topbar-inner">
      ${extra}
      <a class="brand" href="/"><span class="logo">${ICONS.logo}</span><span class="hide-sm">${esc(me.title)}</span></a>
      <span class="spacer"></span>
      <span class="conn" id="conn" data-state="offline"><i></i><span class="hide-sm" id="conn-text">menghubungkan…</span></span>
      <button class="btn icon ghost" id="theme" type="button"></button>
      <span class="userchip">${avatar(me.user)}<span><span class="hide-sm">${esc(me.user.name)}</span> <span class="role">${esc(me.user.role)}</span></span></span>
      <form method="post" action="/logout" style="margin:0"><button class="btn icon ghost" title="Keluar" type="submit">${ICONS.logout}</button></form>
    </div>`;
  applyTheme(document.documentElement.dataset.theme || "light");
  document.getElementById("theme").addEventListener("click", toggleTheme);
}

export function setConn(state, text) {
  const el = document.getElementById("conn");
  if (!el) return;
  el.dataset.state = state;
  const t = document.getElementById("conn-text");
  if (t) t.textContent = text;
}

// Live events for the signed-in user (EventSource reconnects by itself).
export function liveEvents(onEvent) {
  let es;
  const open = () => {
    es = new EventSource("/api/events");
    es.onmessage = (e) => {
      try {
        onEvent(JSON.parse(e.data));
      } catch {}
    };
    es.onerror = () => onEvent({ type: "offline" });
  };
  open();
  return () => es && es.close();
}
