// Test runner: renders one document and keeps the tester's progress on the
// server. Progress belongs to the signed-in user, so the same user continues
// on any device. Changes are sent as small ops and merged per step on the
// server (last write per step wins); other tabs of the same user update live.
//
// Document markup (see docs/manual-tests/README.md):
//   <section data-phase="id" data-title="…">  a phase
//   <article data-step="id" data-title="…" data-who="Admin"> a step
//     <div class="expect">…</div>         expected result
//   <span class="chip">text</span>       click to copy (also every <code> in a step)
//   <input data-var="key" placeholder>   value saved with the progress (per user)
//   <span data-ref="key"></span>         shows a saved value
//   <a class="app-link" href="{{app}}/promotion">  {{key}} in hrefs is filled from vars / data-default

import { ICONS, api, avatar, esc, fmtTime, liveEvents, mountTopbar, relTime, setConn, toast } from "./common.js";

const slug = document.body.dataset.slug;
const DEVICE = Math.random().toString(36).slice(2, 10);
const QUEUE_KEY = `test-hub-queue:${slug}`;
const S_LABEL = { pass: "Pass", fail: "Fail", blocked: "Blocked", skip: "Skipped" };
// Shown on the step buttons (verb form); S_LABEL is the recorded result.
const S_BUTTON = { pass: "Pass", fail: "Fail", blocked: "Blocked", skip: "Skip" };
const S_HINT = {
  pass: "Hasil sesuai ekspektasi (p)",
  fail: "Hasil tidak sesuai / bug — tulis catatan (f)",
  blocked: "Tidak bisa dijalankan: terhalang dependensi atau langkah lain (b)",
  skip: "Sengaja tidak dijalankan: opsional atau tidak relevan (s)",
};
const S_KEYS = { p: "pass", f: "fail", b: "blocked", s: "skip" };

let me;
let doc;
let progress = { rev: 0, steps: {}, vars: {} };
let viewing = null; // user id when an admin views someone else's progress
let stepEls = [];
let focused = -1;
let defaults = {};

const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];
const readOnly = () => viewing && viewing !== me.user.id;

// ------------------------------------------------------------------ sync

let queue = loadQueue();
let sending = false;
let online = true;

function loadQueue() {
  try {
    return JSON.parse(localStorage.getItem(QUEUE_KEY) || "[]");
  } catch {
    return [];
  }
}
function saveQueue() {
  try {
    if (queue.length) localStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
    else localStorage.removeItem(QUEUE_KEY);
  } catch {}
}

// Coalesce: the latest op per step field / var wins inside the queue.
function enqueue(op) {
  const key = op.t === "var" ? `v:${op.k}` : `s:${op.id}:${"note" in op ? "n" : "s"}`;
  queue = queue.filter((q) => (q.t === "var" ? `v:${q.k}` : `s:${q.id}:${"note" in q ? "n" : "s"}`) !== key);
  queue.push(op);
  saveQueue();
  flushSoon();
}

let flushTimer;
function flushSoon(delay = 350) {
  clearTimeout(flushTimer);
  flushTimer = setTimeout(flush, delay);
}

async function flush() {
  if (sending || !queue.length || readOnly()) return;
  sending = true;
  const batch = queue.slice();
  setConn("saving", "menyimpan…");
  try {
    const res = await api(`/api/progress/${encodeURIComponent(slug)}`, {
      method: "POST",
      body: JSON.stringify({ ops: batch, device: DEVICE }),
    });
    queue = queue.slice(batch.length);
    saveQueue();
    mergeServer(res.progress, true);
    online = true;
    setConn("live", `tersimpan ${fmtTime(res.progress.updatedAt, me.timezone, false)}`);
  } catch (err) {
    online = false;
    setConn("offline", "offline — perubahan diantre");
    flushSoon(4000);
  } finally {
    sending = false;
    if (queue.length && online) flushSoon(50);
  }
}

// Server state is the truth, except for fields still waiting in the queue.
function mergeServer(server, fromSelf = false) {
  const pending = new Map();
  for (const op of queue) if (op.t === "step") pending.set(op.id, { ...(pending.get(op.id) || {}), ...op });
  const pendingVars = new Map(queue.filter((q) => q.t === "var").map((q) => [q.k, q.v]));
  progress = { rev: server.rev, updatedAt: server.updatedAt, steps: { ...server.steps }, vars: { ...server.vars } };
  for (const [id, op] of pending) {
    const cur = { ...(progress.steps[id] || { s: null, note: "" }) };
    if ("s" in op) cur.s = op.s;
    if ("note" in op) cur.note = op.note;
    progress.steps[id] = cur;
  }
  for (const [k, v] of pendingVars) progress.vars[k] = { v };
  paintAll(fromSelf);
}

window.addEventListener("online", () => flushSoon(10));
window.addEventListener("pagehide", () => {
  if (!queue.length || readOnly()) return;
  try {
    fetch(`/api/progress/${encodeURIComponent(slug)}`, {
      method: "POST",
      keepalive: true,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ops: queue, device: DEVICE }),
    });
  } catch {}
});

// ------------------------------------------------------------------ model helpers

const stepState = (id) => progress.steps[id] || { s: null, note: "" };
const varValue = (k) => progress.vars[k]?.v ?? defaults[k] ?? "";

function setStatus(id, s) {
  if (readOnly()) return;
  const cur = stepState(id);
  const next = cur.s === s ? null : s;
  progress.steps[id] = { ...cur, s: next, at: new Date().toISOString() };
  enqueue({ t: "step", id, s: next });
  paintStep(id);
  paintSummary();
}

function setNote(id, note) {
  if (readOnly()) return;
  progress.steps[id] = { ...stepState(id), note };
  enqueue({ t: "step", id, note });
  paintStep(id, { keepNote: true });
  paintSummary();
}

function setVar(k, v) {
  if (readOnly()) return;
  progress.vars[k] = { v };
  enqueue({ t: "var", k, v });
  paintVars({ skip: k });
}

// ------------------------------------------------------------------ build

function decorateDoc(root) {
  // Phases: heading + counter.
  let phaseNo = 0;
  for (const sec of $$("section[data-phase]", root)) {
    phaseNo++;
    const head = document.createElement("div");
    head.className = "phase-head";
    head.innerHTML = `<span class="phase-no">${String(phaseNo).padStart(2, "0")}</span><h2>${esc(sec.dataset.title || sec.dataset.phase)}</h2><span class="phase-count" data-phase-count></span>`;
    sec.id = `phase-${sec.dataset.phase}`;
    sec.prepend(head);
  }

  // Steps: header with status buttons, footer with note.
  let n = 0;
  for (const art of $$("article[data-step]", root)) {
    n++;
    const id = art.dataset.step;
    art.classList.add("step");
    art.id = `step-${id}`;
    art.tabIndex = -1;
    const body = document.createElement("div");
    body.className = "step-body";
    while (art.firstChild) body.appendChild(art.firstChild);
    const who = art.dataset.who ? `<span class="who">${esc(art.dataset.who)}</span>` : "";
    art.innerHTML = `
      <div class="step-top">
        <div class="step-title" data-toggle><h3><span class="step-id">${esc(id)}</span>${esc(art.dataset.title || "")}${who}</h3></div>
        <div class="status-seg" role="group" aria-label="Status langkah">
          ${["pass", "fail", "blocked", "skip"].map((s) => `<button type="button" data-s="${s}" aria-pressed="false" title="${S_HINT[s]}">${ICONS[s]}<span>${S_BUTTON[s]}</span></button>`).join("")}
        </div>
      </div>`;
    art.appendChild(body);
    const foot = document.createElement("div");
    foot.className = "step-foot";
    foot.innerHTML = `<textarea class="note" rows="2" placeholder="Catatan — wajib bila Fail: apa yang terjadi, pesan error…"></textarea><span class="step-meta"></span>`;
    art.appendChild(foot);
  }

  // Copy chips: explicit .chip, plus <code> inside steps (not inside <pre>).
  for (const el of $$(".step-body code", root)) if (!el.closest("pre") && !el.closest(".chip")) el.classList.add("chip");
  for (const el of $$(".chip", root)) {
    el.tabIndex = 0;
    el.title = "Klik untuk menyalin";
  }
  for (const pre of $$("pre", root)) {
    pre.classList.add("copy");
    const b = document.createElement("button");
    b.type = "button";
    b.className = "btn sm copy-btn";
    b.innerHTML = `${ICONS.copy} Salin`;
    pre.appendChild(b);
  }

  // Variables: inputs and their defaults.
  for (const input of $$("input[data-var]", root)) {
    if (input.dataset.default) defaults[input.dataset.var] = input.dataset.default;
    const wrap = document.createElement("span");
    wrap.className = "var";
    input.replaceWith(wrap);
    wrap.appendChild(input);
    input.autocomplete = "off";
    input.spellcheck = false;
  }
  for (const el of $$("[data-default][data-ref]", root)) defaults[el.dataset.ref] = el.dataset.default;
  for (const a of $$("a[href]", root)) {
    if (a.getAttribute("href").includes("{{")) a.dataset.tpl = a.getAttribute("href");
    if (/^https?:/i.test(a.getAttribute("href")) || a.dataset.tpl) {
      a.target = "_blank";
      a.rel = "noopener";
    }
  }
}

function build(content) {
  $("#doc-style").textContent = content.style || "";
  const root = $("#doc");
  root.innerHTML = content.html;
  // A document may repeat its own <h1>/<title>; the runner shows the title.
  root.querySelector(":scope > h1")?.remove();
  defaults = {};
  decorateDoc(root);
  stepEls = $$("article.step", root);
  $("#doc-title").textContent = content.title;
  $("#doc-summary").textContent = content.summary || "";
  document.title = `${content.title} · ${me.title}`;
  buildToc();
  paintAll();
}

function buildToc() {
  $("#toc").innerHTML = doc.phases
    .map((p) => `<a href="#phase-${esc(p.id)}" data-phase="${esc(p.id)}"><span>${esc(p.title)}</span><small></small><span class="stack mini"><i class="p"></i><i class="f"></i><i class="b"></i><i class="s"></i></span></a>`)
    .join("");
}

// ------------------------------------------------------------------ paint

function paintStep(id, { keepNote = false } = {}) {
  const el = document.getElementById(`step-${id}`);
  if (!el) return;
  const st = stepState(id);
  el.dataset.status = st.s || "";
  el.classList.toggle("has-note", !!st.note);
  for (const b of $$(".status-seg button", el)) {
    b.setAttribute("aria-pressed", String(b.dataset.s === st.s));
    b.disabled = !!readOnly();
  }
  const ta = $(".note", el);
  if (!keepNote && document.activeElement !== ta) ta.value = st.note || "";
  ta.readOnly = !!readOnly();
  autosize(ta);
  $(".step-meta", el).textContent = st.at && (st.s || st.note) ? `diubah ${relTime(st.at)}` : "";
}

function paintVars({ skip } = {}) {
  for (const input of $$("#doc input[data-var]")) {
    const k = input.dataset.var;
    if (k !== skip && document.activeElement !== input) input.value = progress.vars[k]?.v ?? "";
    if (!input.placeholder && defaults[k]) input.placeholder = defaults[k];
    input.readOnly = !!readOnly();
  }
  for (const el of $$("#doc [data-ref]")) {
    const v = varValue(el.dataset.ref);
    el.textContent = v || `‹${el.dataset.ref}›`;
    el.classList.add("var-ref");
    el.classList.toggle("unset", !v);
    if (v) el.classList.add("chip");
    else el.classList.remove("chip");
  }
  for (const a of $$("#doc a[data-tpl]")) {
    a.href = a.dataset.tpl.replace(/\{\{([a-z0-9_.-]+)\}\}/gi, (_, k) => encodeURI(varValue(k)));
  }
}

function counts(ids) {
  const c = { pass: 0, fail: 0, blocked: 0, skip: 0, notes: 0, done: 0, total: ids.length };
  for (const id of ids) {
    const st = progress.steps[id];
    if (!st) continue;
    if (st.s) {
      c[st.s]++;
      c.done++;
    }
    if (st.note) c.notes++;
  }
  return c;
}

function paintSummary() {
  const c = counts(doc.steps);
  const pct = c.total ? Math.round((100 * c.done) / c.total) : 0;
  $("#ring-fg").style.strokeDashoffset = String(169.6 * (1 - pct / 100));
  $("#ring-text").textContent = `${pct}%`;
  $("#counts").innerHTML = `
    <span><i class="dot pass"></i>Pass <b>${c.pass}</b></span><span><i class="dot fail"></i>Fail <b>${c.fail}</b></span>
    <span><i class="dot blocked"></i>Blocked <b>${c.blocked}</b></span><span><i class="dot skip"></i>Skipped <b>${c.skip}</b></span>
    <span><i class="dot todo"></i>Untested <b>${c.total - c.done}</b></span><span><i class="dot notes"></i>Notes <b>${c.notes}</b></span>`;

  for (const p of doc.phases) {
    const pc = counts(p.steps);
    const a = $(`#toc a[data-phase="${CSS.escape(p.id)}"]`);
    if (a) {
      $("small", a).textContent = `${pc.done}/${pc.total}`;
      a.classList.toggle("complete", pc.total > 0 && pc.done === pc.total && !pc.fail);
      a.classList.toggle("has-fail", pc.fail > 0);
      const bars = $$(".stack i", a);
      const w = (n) => `${pc.total ? (100 * n) / pc.total : 0}%`;
      [pc.pass, pc.fail, pc.blocked, pc.skip].forEach((n, i) => (bars[i].style.width = w(n)));
    }
    const sec = document.getElementById(`phase-${p.id}`);
    if (sec) {
      $("[data-phase-count]", sec).textContent = `${pc.done}/${pc.total} selesai${pc.fail ? ` · ${pc.fail} fail` : ""}`;
      sec.classList.toggle("phase-done", pc.done === pc.total);
      sec.classList.toggle("phase-clean", !pc.fail && !pc.blocked);
      sec.classList.toggle("phase-nonotes", !pc.notes);
    }
  }
}

function paintAll() {
  for (const id of doc.steps) paintStep(id);
  paintVars();
  paintSummary();
}

function autosize(ta) {
  ta.style.height = "auto";
  if (ta.value) ta.style.height = `${Math.min(260, ta.scrollHeight + 2)}px`;
}

// ------------------------------------------------------------------ focus & navigation

function focusStep(i, { scroll = true } = {}) {
  if (!stepEls.length) return;
  focused = Math.max(0, Math.min(stepEls.length - 1, i));
  stepEls.forEach((el, j) => el.classList.toggle("focused", j === focused));
  const el = stepEls[focused];
  if (scroll) el.scrollIntoView({ block: "center", behavior: "smooth" });
}

function visibleSteps() {
  return stepEls.filter((el) => el.offsetParent !== null);
}

function move(delta) {
  const vis = visibleSteps();
  if (!vis.length) return;
  const cur = vis.indexOf(stepEls[focused]);
  const next = vis[Math.max(0, Math.min(vis.length - 1, (cur < 0 ? (delta > 0 ? -1 : vis.length) : cur) + delta))];
  focusStep(stepEls.indexOf(next));
}

function nextTodo() {
  const start = focused < 0 ? 0 : focused + 1;
  const order = [...stepEls.slice(start), ...stepEls.slice(0, start)];
  const el = order.find((e) => !stepState(e.dataset.step).s);
  if (!el) return toast("Semua langkah sudah ditandai. Mantap!");
  el.classList.remove("collapsed");
  focusStep(stepEls.indexOf(el));
  el.classList.add("flash");
  setTimeout(() => el.classList.remove("flash"), 1200);
}

// Scroll-spy for the phase list.
let spy;
function setupSpy() {
  spy?.disconnect();
  spy = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const id = e.target.dataset.phase;
        for (const a of $$("#toc a")) a.classList.toggle("active", a.dataset.phase === id);
      }
    },
    { rootMargin: "-80px 0px -70% 0px" },
  );
  for (const s of $$("section[data-phase]")) spy.observe(s);
}

// ------------------------------------------------------------------ report

function report() {
  const lines = [];
  const c = counts(doc.steps);
  const who = viewing && viewing !== me.user.id ? me.users.find((u) => u.id === viewing)?.name || viewing : me.user.name;
  lines.push(`# Laporan: ${doc.title}`, "");
  lines.push(`- Penguji: ${who}`);
  lines.push(`- Waktu: ${fmtTime(new Date().toISOString(), me.timezone)}`);
  lines.push(`- Hasil: ${c.pass} pass, ${c.fail} fail, ${c.blocked} blocked, ${c.skip} skipped, ${c.total - c.done} untested (${c.total} langkah)`, "");
  const title = (id) => {
    const el = document.getElementById(`step-${id}`);
    return el?.dataset.title || id;
  };
  const section = (label, filter) => {
    const ids = doc.steps.filter(filter);
    if (!ids.length) return;
    lines.push(`## ${label} (${ids.length})`, "");
    for (const id of ids) {
      const st = stepState(id);
      lines.push(`- **${id}** ${title(id)}${st.s ? ` — ${S_LABEL[st.s]}` : ""}`);
      if (st.note) for (const l of st.note.split("\n")) lines.push(`  > ${l}`);
    }
    lines.push("");
  };
  section("Failed", (id) => stepState(id).s === "fail");
  section("Blocked", (id) => stepState(id).s === "blocked");
  section("Other notes", (id) => !["fail", "blocked"].includes(stepState(id).s) && stepState(id).note);
  section("Untested", (id) => !stepState(id).s);
  const vars = Object.entries(progress.vars);
  if (vars.length) {
    lines.push("## Nilai yang dicatat", "");
    for (const [k, v] of vars) lines.push(`- ${k}: ${v.v}`);
    lines.push("");
  }
  return lines.join("\n");
}

// ------------------------------------------------------------------ events

function wire() {
  const root = $("#doc");

  root.addEventListener("click", async (e) => {
    const sb = e.target.closest(".status-seg button");
    if (sb) {
      const art = sb.closest("article.step");
      focusStep(stepEls.indexOf(art), { scroll: false });
      setStatus(art.dataset.step, sb.dataset.s);
      if (sb.dataset.s === "fail" && !stepState(art.dataset.step).note && stepState(art.dataset.step).s === "fail") $(".note", art).focus();
      return;
    }
    const tg = e.target.closest("[data-toggle]");
    if (tg) {
      const art = tg.closest("article.step");
      // Leave any input so keyboard shortcuts act on this step.
      if (document.activeElement?.closest?.("input, textarea, select")) document.activeElement.blur();
      focusStep(stepEls.indexOf(art), { scroll: false });
      return;
    }
    const chip = e.target.closest(".chip");
    if (chip) return copy(chip.textContent.trim(), chip);
    const cb = e.target.closest(".copy-btn");
    if (cb) {
      const pre = cb.closest("pre");
      return copy(($("code", pre) || pre).innerText.replace(/\s*Salin\s*$/, "").trim(), cb);
    }
  });

  root.addEventListener("keydown", (e) => {
    if (e.target.classList?.contains("chip") && (e.key === "Enter" || e.key === " ")) {
      e.preventDefault();
      copy(e.target.textContent.trim(), e.target);
    }
  });

  const noteTimers = new Map();
  root.addEventListener("input", (e) => {
    const ta = e.target.closest(".note");
    if (ta) {
      autosize(ta);
      const id = ta.closest("article.step").dataset.step;
      clearTimeout(noteTimers.get(id));
      noteTimers.set(id, setTimeout(() => setNote(id, ta.value), 500));
      return;
    }
    const v = e.target.closest("input[data-var]");
    if (v) {
      clearTimeout(noteTimers.get(`var:${v.dataset.var}`));
      noteTimers.set(`var:${v.dataset.var}`, setTimeout(() => setVar(v.dataset.var, v.value.trim()), 400));
    }
  });
  root.addEventListener("focusout", (e) => {
    const ta = e.target.closest?.(".note");
    if (ta) {
      const id = ta.closest("article.step").dataset.step;
      if ((stepState(id).note || "") !== ta.value) {
        clearTimeout(noteTimers.get(id));
        setNote(id, ta.value);
      }
    }
  });
  root.addEventListener("focusin", (e) => {
    const art = e.target.closest?.("article.step");
    if (art) focusStep(stepEls.indexOf(art), { scroll: false });
  });

  // filters
  for (const b of $$("#filters button")) {
    b.addEventListener("click", () => {
      for (const x of $$("#filters button")) x.setAttribute("aria-pressed", String(x === b));
      document.body.classList.remove("f-todo", "f-problem", "f-notes");
      if (b.dataset.f) document.body.classList.add(`f-${b.dataset.f}`);
    });
  }

  $("#toc").addEventListener("click", () => document.body.classList.remove("side-open"));
  $("#btn-next").addEventListener("click", nextTodo);
  $("#btn-collapse").addEventListener("click", (e) => {
    const collapse = !stepEls.some((el) => el.classList.contains("collapsed"));
    for (const el of stepEls) el.classList.toggle("collapsed", collapse && stepState(el.dataset.step).s === "pass");
    e.target.textContent = collapse ? "Buka semua" : "Ringkas yang selesai";
  });
  $("#btn-keys").addEventListener("click", () => $("#dlg-keys").showModal());
  $("#btn-report").addEventListener("click", () => {
    $("#report").value = report();
    $("#dlg-report").showModal();
  });
  $("#report-copy").addEventListener("click", (e) => copy($("#report").value, e.target));
  $("#report-download").addEventListener("click", () => {
    const blob = new Blob([$("#report").value], { type: "text/markdown" });
    const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: `${slug}-${viewing || me.user.id}.md` });
    a.click();
    URL.revokeObjectURL(a.href);
  });
  $("#btn-reset").addEventListener("click", async () => {
    const target = viewing || me.user.id;
    const name = target === me.user.id ? "kamu" : target;
    if (!confirm(`Hapus semua status, catatan, dan nilai tercatat milik ${name} di dokumen ini? Tidak bisa dibatalkan.`)) return;
    try {
      queue = [];
      saveQueue();
      const res = await api(`/api/progress/${encodeURIComponent(slug)}?user=${encodeURIComponent(target)}`, { method: "DELETE" });
      mergeServer(res.progress);
      toast("Progres direset.");
    } catch (err) {
      toast(`Gagal reset: ${err.message}`, "bad");
    }
  });
  for (const d of $$("dialog")) {
    d.addEventListener("click", (e) => {
      if (e.target === d || e.target.closest("[data-close]")) d.close();
    });
  }

  document.addEventListener("keydown", (e) => {
    const t = e.target;
    const typing = t.closest?.("input, textarea, select, [contenteditable]");
    if (e.key === "Escape" && typing) return t.blur();
    if (typing || e.ctrlKey || e.metaKey || e.altKey || $("dialog[open]")) return;
    const art = stepEls[focused];
    if (e.key === "j") move(1);
    else if (e.key === "k") move(-1);
    else if (e.key === " ") nextTodo();
    else if (e.key === "?") $("#dlg-keys").showModal();
    else if (art && S_KEYS[e.key]) {
      setStatus(art.dataset.step, S_KEYS[e.key]);
      if (e.key === "f" && stepState(art.dataset.step).s === "fail") {
        e.preventDefault();
        $(".note", art).focus();
      }
    } else if (art && e.key === "u") {
      if (stepState(art.dataset.step).s) setStatus(art.dataset.step, stepState(art.dataset.step).s);
    } else if (art && e.key === "n") {
      e.preventDefault();
      art.classList.remove("collapsed");
      $(".note", art).focus();
    } else if (art && e.key === "x") art.classList.toggle("collapsed");
    else return;
    e.preventDefault();
  });
}

async function copy(text, el) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = Object.assign(document.createElement("textarea"), { value: text });
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    ta.remove();
  }
  el?.classList.add("copied");
  setTimeout(() => el?.classList.remove("copied"), 900);
  toast(text.length > 60 ? "Disalin" : `Disalin: ${text}`);
}

// ------------------------------------------------------------------ viewer (admin)

function setupViewer() {
  if (me.user.role !== "admin" || !me.users) return;
  const box = $("#viewer-box");
  box.hidden = false;
  const sel = $("#viewer");
  sel.innerHTML = me.users.map((u) => `<option value="${esc(u.id)}">${esc(u.id === me.user.id ? `${u.name} (kamu)` : u.name)}</option>`).join("");
  sel.value = me.user.id;
  sel.addEventListener("change", async () => {
    viewing = sel.value === me.user.id ? null : sel.value;
    const banner = $("#viewing");
    if (viewing) {
      const u = me.users.find((x) => x.id === viewing);
      banner.hidden = false;
      banner.innerHTML = `${avatar(u)} <span>Melihat progres <b>${esc(u.name)}</b> (hanya baca). Reset tetap bisa dilakukan admin.</span>`;
    } else banner.hidden = true;
    await loadProgress();
  });
}

async function loadProgress() {
  const q = viewing ? `?user=${encodeURIComponent(viewing)}` : "";
  const res = await api(`/api/progress/${encodeURIComponent(slug)}${q}`);
  if (viewing) {
    progress = res.progress;
    paintAll();
  } else mergeServer(res.progress);
}

// ------------------------------------------------------------------ main

(async () => {
  me = await api("/api/me");
  mountTopbar(me, { extra: `<button class="btn icon ghost side-toggle" id="side-toggle" type="button" title="Daftar fase">${ICONS.menu}</button><a class="btn icon ghost" href="/" title="Semua dokumen">${ICONS.back}</a>` });
  $("#side-toggle").addEventListener("click", () => document.body.classList.toggle("side-open"));
  document.addEventListener("click", (e) => {
    if (document.body.classList.contains("side-open") && !e.target.closest("#side, #side-toggle")) document.body.classList.remove("side-open");
  });
  try {
    doc = await api(`/api/docs/${encodeURIComponent(slug)}`);
  } catch (err) {
    $("#doc").innerHTML = `<div class="empty">Gagal memuat dokumen: ${esc(err.message)}</div>`;
    return;
  }
  build(doc);
  wire();
  setupViewer();
  setupSpy();
  await loadProgress();
  if (queue.length) {
    toast(`${queue.length} perubahan offline dikirim ulang`);
    flushSoon(10);
  }
  const hash = decodeURIComponent(location.hash.slice(1));
  const fromHash = stepEls.findIndex((el) => el.id === hash);
  if (fromHash >= 0) focusStep(fromHash);

  liveEvents(async (ev) => {
    if (ev.type === "hello") {
      setConn("live", "live");
      // Catch up on anything missed while disconnected.
      loadProgress().catch(() => {});
      if (queue.length) flushSoon(10);
    } else if (ev.type === "offline") setConn("offline", "terputus — mencoba lagi");
    else if (ev.type === "progress" && ev.slug === slug && !viewing) {
      if (ev.device !== DEVICE && ev.rev > progress.rev) {
        mergeServer(ev.progress);
        if (ev.device === "reset") toast("Progres direset dari perangkat lain");
      }
    } else if (ev.type === "summary" && ev.slug === slug && viewing) {
      loadProgress().catch(() => {});
    } else if (ev.type === "docs") {
      try {
        const fresh = await api(`/api/docs/${encodeURIComponent(slug)}`);
        if (fresh.modifiedAt !== doc.modifiedAt) {
          const y = scrollY;
          doc = fresh;
          build(doc);
          setupSpy();
          scrollTo(0, y);
          toast("Dokumen diperbarui");
        }
      } catch {}
    }
  });
})();
