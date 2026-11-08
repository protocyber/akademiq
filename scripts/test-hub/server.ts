// AkademiQ manual-test hub.
//
// Serves the manual test documents under `docs.dir` (see hub.yaml) and keeps
// every tester's progress on the server, per user and per document. Logging in
// as the same user on another device continues where you left off: no tester
// codes, no resume links. Open tabs of the same user stay in sync live (SSE).
//
// Routes
//   GET  /                         document index (with team progress)
//   GET  /d/<slug>                 test runner for one document
//   GET  /login, POST /login       sign in;  POST /logout  sign out
//   GET  /api/me                   current user
//   GET  /api/docs                 index data
//   GET  /api/docs/<slug>          document content + step ids
//   GET  /api/progress/<slug>      progress (?user=<id>, admin only for others)
//   POST /api/progress/<slug>      apply ops [{t:"step",id,s?,note?}|{t:"var",k,v}]
//   DELETE /api/progress/<slug>    reset (?user=<id>, admin only for others)
//   GET  /api/events               server-sent events for the current user
//   GET  /healthz
//
// Config is hub.yaml (compose-style, ${VAR:-default} interpolation), re-read
// whenever the file changes. Passwords are argon2id hashes (bun cli.ts hash).

import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { basename, join, resolve, sep } from "node:path";
import { loadConfigFile, type HubConfig, type HubUser } from "./config.ts";

const APP_DIR = import.meta.dir;
const CONFIG_PATH = resolve(process.env.HUB_CONFIG || join(APP_DIR, "hub.yaml"));
const REPO_DIR = resolve(process.env.REPO_DIR || join(APP_DIR, "..", ".."));
const STATE_DIR = resolve(process.env.STATE_DIR || join(APP_DIR, ".state"));
const PUBLIC_DIR = join(APP_DIR, "public");
const COOKIE = "hub_session";
const SESSION_TTL_S = 60 * 60 * 24 * 30;
const MAX_BODY = 256 * 1024;
const STATUSES = new Set(["pass", "fail", "blocked", "skip"]);

// ------------------------------------------------------------------ config

let config: HubConfig;
let configMtime = 0;

function currentConfig(): HubConfig {
  let mtime = 0;
  try {
    mtime = statSync(CONFIG_PATH).mtimeMs;
  } catch {
    if (!config) throw new Error(`config not found: ${CONFIG_PATH}`);
    return config;
  }
  if (mtime !== configMtime) {
    try {
      const next = loadConfigFile(CONFIG_PATH);
      const reloaded = configMtime !== 0;
      config = next;
      configMtime = mtime;
      const users = Object.keys(next.users);
      log(`${reloaded ? "reloaded" : "loaded"} ${CONFIG_PATH}: ${users.length} user(s) [${users.join(", ")}]`);
      for (const w of next.warnings) log(`config warning: ${w}`);
    } catch (err) {
      if (!config) throw err;
      log(`config error, keeping the previous config: ${(err as Error).message}`);
      configMtime = mtime;
    }
  }
  return config;
}

function log(message: string) {
  console.log(`[test-hub] ${new Date().toISOString()} ${message}`);
}

// ------------------------------------------------------------------ docs

type DocInfo = {
  slug: string;
  file: string;
  title: string;
  summary: string;
  steps: string[];
  phases: { id: string; title: string; steps: string[] }[];
  mtime: number;
};

const docCache = new Map<string, DocInfo>();

function docsDir(): string {
  return resolve(REPO_DIR, currentConfig().docs.dir);
}

function attr(tag: string, name: string): string | null {
  const m = tag.match(new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, "i"));
  return m ? (m[2] ?? m[3] ?? "") : null;
}

function parseDoc(file: string, mtime: number): DocInfo {
  const raw = readFileSync(file, "utf8");
  const title = (raw.match(/<title>([\s\S]*?)<\/title>/i)?.[1] ?? basename(file, ".html")).trim().replace(/\s+/g, " ");
  const summary = (raw.match(/<meta\s+name=["']description["']\s+content=["']([^"']*)["']/i)?.[1] ?? "").trim();
  const steps: string[] = [];
  const phases: DocInfo["phases"] = [];
  // Phases and steps in document order. A step belongs to the last phase seen.
  const tagRe = /<(section|article)\b[^>]*>/gi;
  for (const m of raw.matchAll(tagRe)) {
    const tag = m[0];
    const phase = attr(tag, "data-phase");
    if (phase !== null) {
      phases.push({ id: phase, title: attr(tag, "data-title") ?? phase, steps: [] });
      continue;
    }
    const step = attr(tag, "data-step");
    if (step !== null) {
      steps.push(step);
      if (phases.length) phases[phases.length - 1].steps.push(step);
    }
  }
  return { slug: basename(file, ".html"), file, title, summary, steps, phases, mtime };
}

function listDocs(): DocInfo[] {
  const dir = docsDir();
  let names: string[] = [];
  try {
    names = readdirSync(dir).filter((n) => n.endsWith(".html") && !n.startsWith("_"));
  } catch {
    return [];
  }
  const out: DocInfo[] = [];
  for (const name of names) {
    const file = join(dir, name);
    let mtime: number;
    try {
      const st = statSync(file);
      if (!st.isFile()) continue;
      mtime = st.mtimeMs;
    } catch {
      continue;
    }
    const cached = docCache.get(file);
    if (cached && cached.mtime === mtime) {
      out.push(cached);
      continue;
    }
    try {
      const doc = parseDoc(file, mtime);
      docCache.set(file, doc);
      out.push(doc);
    } catch (err) {
      log(`cannot parse ${file}: ${(err as Error).message}`);
    }
  }
  return out.sort((a, b) => b.slug.localeCompare(a.slug));
}

function findDoc(slug: string): DocInfo | null {
  return listDocs().find((d) => d.slug === slug) ?? null;
}

function docContent(doc: DocInfo) {
  const raw = readFileSync(doc.file, "utf8");
  const body = raw.match(/<body[^>]*>([\s\S]*)<\/body>/i)?.[1] ?? raw;
  const styles = [...raw.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)].map((m) => m[1]).join("\n");
  return { html: body, style: styles };
}

// Watch for edited documents and tell open runners.
let docSignature = "";
setInterval(() => {
  try {
    const sig = listDocs()
      .map((d) => `${d.slug}:${d.mtime}`)
      .join("|");
    if (docSignature && sig !== docSignature) broadcastAll({ type: "docs" });
    docSignature = sig;
  } catch {
    /* ignore */
  }
}, 2000);

// ------------------------------------------------------------------ progress

type StepState = { s: string | null; note: string; at: string };
type Progress = {
  rev: number;
  updatedAt: string | null;
  steps: Record<string, StepState>;
  vars: Record<string, { v: string; at: string }>;
};

const safeId = (v: string) => /^[a-z0-9][a-z0-9._-]{0,63}$/i.test(v);

function progressFile(user: string, slug: string) {
  return join(STATE_DIR, "progress", user, `${slug}.json`);
}

function emptyProgress(): Progress {
  return { rev: 0, updatedAt: null, steps: {}, vars: {} };
}

function readProgress(user: string, slug: string): Progress {
  try {
    const p = JSON.parse(readFileSync(progressFile(user, slug), "utf8"));
    return { ...emptyProgress(), ...p };
  } catch {
    return emptyProgress();
  }
}

function writeProgress(user: string, slug: string, p: Progress) {
  const file = progressFile(user, slug);
  mkdirSync(join(STATE_DIR, "progress", user), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(p));
  renameSync(tmp, file);
}

// One in-process writer at a time per file keeps read-modify-write safe.
const locks = new Map<string, Promise<unknown>>();
async function withLock<T>(key: string, fn: () => T | Promise<T>): Promise<T> {
  const prev = locks.get(key) ?? Promise.resolve();
  const next = prev.then(fn, fn);
  locks.set(key, next.catch(() => {}));
  return next;
}

type Op = { t: "step"; id: string; s?: string | null; note?: string } | { t: "var"; k: string; v: string };

function applyOps(p: Progress, ops: Op[], doc: DocInfo): Op[] {
  const now = new Date().toISOString();
  const known = new Set(doc.steps);
  const applied: Op[] = [];
  for (const op of ops) {
    if (op.t === "step" && typeof op.id === "string" && known.has(op.id)) {
      const cur = p.steps[op.id] ?? { s: null, note: "", at: now };
      if ("s" in op) {
        if (op.s !== null && !STATUSES.has(String(op.s))) continue;
        cur.s = op.s ?? null;
      }
      if (typeof op.note === "string") cur.note = op.note.slice(0, 4000);
      cur.at = now;
      if (!cur.s && !cur.note) delete p.steps[op.id];
      else p.steps[op.id] = cur;
      applied.push(op);
    } else if (op.t === "var" && typeof op.k === "string" && safeId(op.k) && typeof op.v === "string") {
      if (op.v === "") delete p.vars[op.k];
      else p.vars[op.k] = { v: op.v.slice(0, 500), at: now };
      applied.push(op);
    }
  }
  if (applied.length) {
    p.rev += 1;
    p.updatedAt = now;
  }
  return applied;
}

function summarize(p: Progress, doc: DocInfo) {
  const c = { pass: 0, fail: 0, blocked: 0, skip: 0, notes: 0 };
  for (const id of doc.steps) {
    const st = p.steps[id];
    if (!st) continue;
    if (st.s && st.s in c) c[st.s as keyof typeof c]++;
    if (st.note) c.notes++;
  }
  const done = c.pass + c.fail + c.blocked + c.skip;
  return { ...c, done, total: doc.steps.length, updatedAt: p.updatedAt };
}

// ------------------------------------------------------------------ sessions

function sessionSecret(): Buffer {
  const file = join(STATE_DIR, "session.key");
  if (!existsSync(file)) {
    mkdirSync(STATE_DIR, { recursive: true });
    writeFileSync(file, randomBytes(32).toString("hex"), { mode: 0o600 });
  }
  return Buffer.from(readFileSync(file, "utf8").trim(), "hex");
}

const SECRET = (() => {
  mkdirSync(STATE_DIR, { recursive: true });
  return sessionSecret();
})();

// The session is bound to the password hash: changing a password signs every
// device of that user out.
function pwTag(user: HubUser) {
  return createHash("sha256").update(user.password_hash ?? "").digest("hex").slice(0, 16);
}

function sign(payload: string) {
  return createHmac("sha256", SECRET).update(payload).digest("base64url");
}

function makeSession(user: HubUser) {
  const payload = Buffer.from(JSON.stringify({ u: user.id, exp: Math.floor(Date.now() / 1000) + SESSION_TTL_S, v: pwTag(user) })).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

function readCookie(req: Request, name: string): string | null {
  const raw = req.headers.get("cookie") || "";
  for (const part of raw.split(";")) {
    const [k, ...rest] = part.trim().split("=");
    if (k === name) return rest.join("=");
  }
  return null;
}

function sessionUser(req: Request): HubUser | null {
  const token = readCookie(req, COOKIE);
  if (!token) return null;
  const [payload, mac] = token.split(".");
  if (!payload || !mac) return null;
  const expected = Buffer.from(sign(payload));
  const given = Buffer.from(mac);
  if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    if (typeof data.exp !== "number" || data.exp < Date.now() / 1000) return null;
    const user = currentConfig().users[data.u];
    if (!user || user.disabled || data.v !== pwTag(user)) return null;
    return user;
  } catch {
    return null;
  }
}

function isSecure(req: Request) {
  const proto = req.headers.get("x-forwarded-proto");
  if (proto) return proto === "https";
  return currentConfig().server.public_url.startsWith("https://");
}

function cookieHeader(req: Request, value: string, maxAge: number) {
  return `${COOKIE}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${isSecure(req) ? "; Secure" : ""}`;
}

// Slow down repeated failures per client address.
const failures = new Map<string, { n: number; until: number }>();
function clientKey(req: Request, server: ReturnType<typeof Bun.serve>) {
  return req.headers.get("x-forwarded-for")?.split(",")[0].trim() || server.requestIP(req)?.address || "?";
}

// ------------------------------------------------------------------ SSE

type Client = { user: string; controller: ReadableStreamDefaultController<Uint8Array> };
const clients = new Set<Client>();
const enc = new TextEncoder();

function sendTo(client: Client, data: unknown) {
  try {
    client.controller.enqueue(enc.encode(`data: ${JSON.stringify(data)}\n\n`));
  } catch {
    clients.delete(client);
  }
}

function broadcastUser(user: string, data: unknown) {
  for (const c of clients) if (c.user === user) sendTo(c, data);
}

function broadcastAll(data: unknown) {
  for (const c of clients) sendTo(c, data);
}

setInterval(() => {
  for (const c of clients) {
    try {
      c.controller.enqueue(enc.encode(`: ping\n\n`));
    } catch {
      clients.delete(c);
    }
  }
}, 25000);

function eventStream(user: HubUser) {
  let client: Client;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      client = { user: user.id, controller };
      clients.add(client);
      controller.enqueue(enc.encode(`retry: 3000\ndata: ${JSON.stringify({ type: "hello" })}\n\n`));
    },
    cancel() {
      clients.delete(client);
    },
  });
  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    },
  });
}

// ------------------------------------------------------------------ http helpers

const SECURITY_HEADERS = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "same-origin",
  "x-frame-options": "DENY",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...SECURITY_HEADERS },
  });
}

function html(body: string, status = 200, extra: Record<string, string> = {}) {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", ...SECURITY_HEADERS, ...extra },
  });
}

function redirect(location: string, extra: Record<string, string> = {}) {
  return new Response(null, { status: 303, headers: { location, "cache-control": "no-store", ...extra } });
}

const esc = (v: unknown) =>
  String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

function safeNext(v: string | null) {
  const next = v || "/";
  return next.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\") ? next : "/";
}

function shell(file: string, vars: Record<string, string>) {
  let page = readFileSync(join(PUBLIC_DIR, file), "utf8");
  const cfg = currentConfig();
  const all = { TITLE: esc(cfg.server.title), ...vars };
  for (const [k, v] of Object.entries(all)) page = page.replaceAll(`{{${k}}}`, v);
  return page;
}

async function readJSON(req: Request): Promise<any> {
  const len = Number(req.headers.get("content-length") || 0);
  if (len > MAX_BODY) throw new Error("too large");
  const text = await req.text();
  if (text.length > MAX_BODY) throw new Error("too large");
  return JSON.parse(text || "{}");
}

const TYPES: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

function asset(name: string) {
  const file = resolve(PUBLIC_DIR, name);
  if (!file.startsWith(PUBLIC_DIR + sep) || !existsSync(file)) return new Response("not found", { status: 404 });
  const ext = file.slice(file.lastIndexOf("."));
  return new Response(Bun.file(file), {
    headers: { "content-type": TYPES[ext] ?? "application/octet-stream", "cache-control": "no-cache", ...SECURITY_HEADERS },
  });
}

// Files next to the documents (screenshots and the like), never outside them.
function docAsset(name: string) {
  const dir = docsDir();
  const file = resolve(dir, name);
  if (!file.startsWith(dir + sep) || file.endsWith(".html") || !existsSync(file)) return new Response("not found", { status: 404 });
  return new Response(Bun.file(file), { headers: { "cache-control": "no-cache", ...SECURITY_HEADERS } });
}

function publicUser(u: HubUser) {
  return { id: u.id, name: u.name, role: u.role };
}

// ------------------------------------------------------------------ handlers

async function handleLogin(req: Request, url: URL, server: ReturnType<typeof Bun.serve>) {
  const next = safeNext(url.searchParams.get("next"));
  const page = (error = "", username = "") =>
    shell("login.html", {
      ERROR: error ? `<div class="alert alert-bad" role="alert">${esc(error)}</div>` : "",
      USERNAME: esc(username),
      NEXT: esc(next),
    });

  if (req.method === "GET") {
    if (sessionUser(req)) return redirect(next);
    return html(page());
  }
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const key = clientKey(req, server);
  const f = failures.get(key);
  if (f && f.until > Date.now()) {
    return html(page("Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi."), 429);
  }

  const form = await req.formData();
  const username = String(form.get("username") || "").trim().toLowerCase();
  const password = String(form.get("password") || "");
  const formNext = safeNext(String(form.get("next") || next));

  await Bun.sleep(300);
  const user = currentConfig().users[username];
  let ok = false;
  if (user && !user.disabled && user.password_hash && password) {
    try {
      ok = await Bun.password.verify(password, user.password_hash);
    } catch {
      ok = false;
    }
  }
  if (!ok) {
    const n = (f?.n ?? 0) + 1;
    failures.set(key, { n, until: n >= 5 ? Date.now() + Math.min(60000, 2000 * 2 ** (n - 5)) : 0 });
    log(`login failed for "${username}" from ${key}`);
    return html(page("Nama pengguna atau kata sandi salah.", username), 401);
  }
  failures.delete(key);
  log(`login ${user!.id} from ${key}`);
  return redirect(formNext, { "set-cookie": cookieHeader(req, makeSession(user!), SESSION_TTL_S) });
}

async function handleAPI(req: Request, url: URL, user: HubUser) {
  const path = url.pathname;
  const cfg = currentConfig();

  if (path === "/api/me") {
    return json({
      user: publicUser(user),
      title: cfg.server.title,
      timezone: cfg.server.timezone,
      users: user.role === "admin" ? Object.values(cfg.users).filter((u) => !u.disabled).map(publicUser) : undefined,
    });
  }

  if (path === "/api/events") return eventStream(user);

  if (path === "/api/docs" && req.method === "GET") {
    const users = Object.values(cfg.users).filter((u) => !u.disabled);
    const docs = listDocs().map((doc) => ({
      slug: doc.slug,
      title: doc.title,
      summary: doc.summary,
      total: doc.steps.length,
      phases: doc.phases.length,
      modifiedAt: new Date(doc.mtime).toISOString(),
      progress: users
        .map((u) => ({ user: publicUser(u), ...summarize(readProgress(u.id, doc.slug), doc) }))
        .filter((p) => p.user.id === user.id || p.updatedAt),
    }));
    return json({ docs });
  }

  let m = path.match(/^\/api\/docs\/([^/]+)$/);
  if (m && req.method === "GET") {
    const doc = findDoc(decodeURIComponent(m[1]));
    if (!doc) return json({ error: "unknown document" }, 404);
    return json({
      slug: doc.slug,
      title: doc.title,
      summary: doc.summary,
      steps: doc.steps,
      phases: doc.phases,
      modifiedAt: new Date(doc.mtime).toISOString(),
      ...docContent(doc),
    });
  }

  m = path.match(/^\/api\/progress\/([^/]+)$/);
  if (m) {
    const doc = findDoc(decodeURIComponent(m[1]));
    if (!doc) return json({ error: "unknown document" }, 404);
    const target = (url.searchParams.get("user") || user.id).toLowerCase();
    const self = target === user.id;
    if (!self && user.role !== "admin") return json({ error: "forbidden" }, 403);
    if (!cfg.users[target]) return json({ error: "unknown user" }, 404);
    const lockKey = `${target}/${doc.slug}`;

    if (req.method === "GET") {
      return json({ user: publicUser(cfg.users[target]), progress: readProgress(target, doc.slug) });
    }

    if (req.method === "POST") {
      if (!self) return json({ error: "progress of another user is read-only" }, 403);
      let body: any;
      try {
        body = await readJSON(req);
      } catch {
        return json({ error: "invalid JSON body" }, 400);
      }
      if (!Array.isArray(body.ops) || body.ops.length > 500) return json({ error: "ops must be an array (max 500)" }, 400);
      const device = typeof body.device === "string" ? body.device.slice(0, 40) : "";
      return withLock(lockKey, () => {
        const p = readProgress(target, doc.slug);
        const applied = applyOps(p, body.ops, doc);
        if (applied.length) {
          writeProgress(target, doc.slug, p);
          broadcastUser(target, { type: "progress", slug: doc.slug, device, rev: p.rev, progress: p });
          broadcastAll({ type: "summary", slug: doc.slug });
        }
        return json({ rev: p.rev, progress: p });
      });
    }

    if (req.method === "DELETE") {
      return withLock(lockKey, () => {
        const p = readProgress(target, doc.slug);
        const fresh = { ...emptyProgress(), rev: p.rev + 1, updatedAt: new Date().toISOString() };
        writeProgress(target, doc.slug, fresh);
        log(`progress reset: ${target}/${doc.slug} by ${user.id}`);
        broadcastUser(target, { type: "progress", slug: doc.slug, device: "reset", rev: fresh.rev, progress: fresh });
        broadcastAll({ type: "summary", slug: doc.slug });
        return json({ rev: fresh.rev, progress: fresh });
      });
    }
    return json({ error: "method not allowed" }, 405);
  }

  return json({ error: "not found" }, 404);
}

async function handle(req: Request, server: ReturnType<typeof Bun.serve>): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (path === "/healthz") return new Response("ok");
  if (path.startsWith("/assets/")) return asset(decodeURIComponent(path.slice(8)));
  if (path === "/login") return handleLogin(req, url, server);
  if (path === "/logout") {
    return redirect("/login", { "set-cookie": cookieHeader(req, "", 0) });
  }

  const user = sessionUser(req);
  if (!user) {
    if (path.startsWith("/api/")) return json({ error: "login required" }, 401);
    return redirect(`/login?next=${encodeURIComponent(path + url.search)}`);
  }

  if (path.startsWith("/api/")) return handleAPI(req, url, user);
  if (path === "/" || path === "/index.html") return html(shell("index.html", {}));

  const m = path.match(/^\/d\/([^/]+)\/?$/);
  if (m) {
    const doc = findDoc(decodeURIComponent(m[1]));
    if (!doc) return html(shell("404.html", {}), 404);
    return html(shell("runner.html", { DOC_TITLE: esc(doc.title), SLUG: esc(doc.slug) }));
  }
  const f = path.match(/^\/d\/[^/]+\/(.+)$/);
  if (f) return docAsset(decodeURIComponent(f[1]));

  return html(shell("404.html", {}), 404);
}

// ------------------------------------------------------------------ main

const cfg = currentConfig();
const port = Number(process.env.PORT || cfg.server.port || 8090);
const server = Bun.serve({
  port,
  hostname: process.env.HOST || "0.0.0.0",
  idleTimeout: 0, // SSE connections stay open
  async fetch(req, srv) {
    try {
      return await handle(req, srv);
    } catch (err) {
      console.error(err);
      return json({ error: "internal error" }, 500);
    }
  },
});

log(`listening on http://${server.hostname}:${server.port}`);
log(`documents in ${docsDir()}`);
log(`state in ${STATE_DIR}`);
