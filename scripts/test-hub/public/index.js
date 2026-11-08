import { ICONS, api, avatar, esc, liveEvents, mountTopbar, relTime, setConn } from "./common.js";

const listEl = document.getElementById("list");
const qEl = document.getElementById("q");
document.getElementById("search-icon").innerHTML = ICONS.search;

let me;
let docs = [];

function stack(p) {
  const pct = (n) => (p.total ? (100 * n) / p.total : 0);
  return `<div class="stack" title="${p.done}/${p.total}">
    <i class="p" style="width:${pct(p.pass)}%"></i><i class="f" style="width:${pct(p.fail)}%"></i>
    <i class="b" style="width:${pct(p.blocked)}%"></i><i class="s" style="width:${pct(p.skip)}%"></i></div>`;
}

function personRow(p) {
  const bits = [];
  if (p.fail) bits.push(`<span style="color:var(--fail)">${p.fail} fail</span>`);
  if (p.blocked) bits.push(`<span style="color:var(--blocked)">${p.blocked} blocked</span>`);
  const pct = p.total ? Math.round((100 * p.done) / p.total) : 0;
  return `<div class="person">${avatar(p.user)}
    <div>${stack(p)}<small>${esc(p.user.id === me.user.id ? "Kamu" : p.user.name)} · ${p.done}/${p.total}${bits.length ? " · " + bits.join(" · ") : ""}${p.updatedAt ? ` · aktif ${relTime(p.updatedAt)}` : ""}</small></div>
    <small style="font-variant-numeric:tabular-nums">${pct}%</small></div>`;
}

function render() {
  const q = qEl.value.trim().toLowerCase();
  const shown = docs.filter((d) => !q || `${d.title} ${d.slug} ${d.summary}`.toLowerCase().includes(q));
  if (!shown.length) {
    listEl.innerHTML = `<div class="empty">${docs.length ? "Tidak ada dokumen yang cocok." : "Belum ada dokumen tes di folder docs."}</div>`;
    return;
  }
  listEl.innerHTML = shown
    .map((d) => {
      const mine = d.progress.find((p) => p.user.id === me.user.id);
      const others = d.progress.filter((p) => p.user.id !== me.user.id);
      return `<a class="doc-card" href="/d/${encodeURIComponent(d.slug)}">
        <div><h3>${esc(d.title)}</h3>${d.summary ? `<p style="margin-top:6px">${esc(d.summary)}</p>` : ""}</div>
        <div class="doc-meta">
          <span>${ICONS.list} ${d.total} langkah · ${d.phases} fase</span>
          <span>${ICONS.clock} diubah ${relTime(d.modifiedAt)}</span>
        </div>
        <div class="people">${mine ? personRow(mine) : ""}${others.map(personRow).join("")}</div>
      </a>`;
    })
    .join("");
}

async function load() {
  try {
    docs = (await api("/api/docs")).docs;
    render();
  } catch (err) {
    listEl.innerHTML = `<div class="empty">Gagal memuat daftar: ${esc(err.message)}</div>`;
  }
}

let reloadTimer;
function soon() {
  clearTimeout(reloadTimer);
  reloadTimer = setTimeout(load, 400);
}

qEl.addEventListener("input", render);
document.addEventListener("keydown", (e) => {
  if (e.key === "/" && document.activeElement !== qEl) {
    e.preventDefault();
    qEl.focus();
  }
});

(async () => {
  me = await api("/api/me");
  mountTopbar(me);
  document.title = me.title;
  await load();
  liveEvents((ev) => {
    if (ev.type === "hello") setConn("live", "live");
    else if (ev.type === "offline") setConn("offline", "terputus");
    else if (ev.type === "summary" || ev.type === "docs" || ev.type === "progress") soon();
  });
  setInterval(render, 60000); // keep "x menit lalu" fresh
})();
