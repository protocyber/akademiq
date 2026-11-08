// Command-line helper for hub.yaml: manage users without hand-editing hashes.
//
//   bun cli.ts hash                         read a password (stdin), print its argon2id hash
//   bun cli.ts users                        list users
//   bun cli.ts user-add <id> [--name N] [--role admin|tester]   add a user, prompts for password
//   bun cli.ts passwd <id>                  set a new password
//   bun cli.ts user-rm <id>                 remove a user (progress files are kept)
//   bun cli.ts user-disable <id> | user-enable <id>
//   bun cli.ts check                        validate hub.yaml
//
// Edits keep comments and layout: only the lines of the touched user change.
// The password is read from stdin (HUB_PASSWORD env is accepted for scripts);
// it is never printed.

import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { loadConfigFile } from "./config.ts";

const CONFIG = resolve(process.env.HUB_CONFIG || join(import.meta.dir, "hub.yaml"));
const [cmd, ...args] = process.argv.slice(2);

function die(msg: string): never {
  console.error(msg);
  process.exit(1);
}

function flag(name: string): string | undefined {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
}

async function readPassword(prompt: string): Promise<string> {
  if (process.env.HUB_PASSWORD) return process.env.HUB_PASSWORD;
  const tty = process.stdin.isTTY;
  if (tty) {
    process.stderr.write(prompt);
    Bun.spawnSync(["stty", "-echo"], { stdin: "inherit" });
  }
  let line = "";
  try {
    for await (const chunk of console) {
      line = chunk;
      break;
    }
  } finally {
    if (tty) {
      Bun.spawnSync(["stty", "echo"], { stdin: "inherit" });
      process.stderr.write("\n");
    }
  }
  return line.replace(/\r?\n$/, "");
}

async function newHash(): Promise<string> {
  const a = await readPassword("Password baru: ");
  if (a.length < 8) die("Password minimal 8 karakter.");
  if (process.stdin.isTTY && !process.env.HUB_PASSWORD) {
    const b = await readPassword("Ulangi password: ");
    if (a !== b) die("Password tidak sama.");
  }
  return Bun.password.hash(a, { algorithm: "argon2id" });
}

function readLines(): string[] {
  if (!existsSync(CONFIG)) die(`${CONFIG} belum ada. Jalankan: make init`);
  return readFileSync(CONFIG, "utf8").split("\n");
}

function save(lines: string[]) {
  const tmp = `${CONFIG}.tmp`;
  writeFileSync(tmp, lines.join("\n"), { mode: 0o600 });
  renameSync(tmp, CONFIG);
}

// Locate `users:` and the block of one user inside it (2-space indent keys).
function usersBlock(lines: string[]) {
  const start = lines.findIndex((l) => /^users:\s*(#.*)?$/.test(l));
  if (start < 0) return { start: -1, end: -1 };
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^\S/.test(lines[i]) && !lines[i].startsWith("#")) {
      end = i;
      break;
    }
  }
  return { start, end };
}

function userRange(lines: string[], id: string) {
  const { start, end } = usersBlock(lines);
  if (start < 0) return null;
  for (let i = start + 1; i < end; i++) {
    const m = lines[i].match(/^  ([A-Za-z0-9._-]+):\s*(#.*)?$/);
    if (m && m[1].toLowerCase() === id) {
      let j = i + 1;
      while (j < end && (/^ {4,}/.test(lines[j]) || lines[j].trim() === "")) j++;
      // keep trailing blank lines outside the block
      while (j > i + 1 && lines[j - 1].trim() === "") j--;
      return { from: i, to: j };
    }
  }
  return null;
}

function setField(lines: string[], id: string, key: string, value: string | null) {
  const r = userRange(lines, id);
  if (!r) die(`User "${id}" tidak ada.`);
  for (let i = r.from + 1; i < r.to; i++) {
    if (new RegExp(`^ {4}${key}:`).test(lines[i])) {
      if (value === null) lines.splice(i, 1);
      else lines[i] = `    ${key}: ${value}`;
      return;
    }
  }
  if (value !== null) lines.splice(r.to, 0, `    ${key}: ${value}`);
}

const yamlString = (s: string) => JSON.stringify(s);
const validId = (id: string) => /^[a-z0-9][a-z0-9._-]{0,31}$/.test(id);

switch (cmd) {
  case "hash": {
    console.log(await newHash());
    break;
  }
  case "users": {
    const cfg = loadConfigFile(CONFIG);
    const rows = Object.values(cfg.users);
    if (!rows.length) console.log("(belum ada user)");
    for (const u of rows) {
      console.log(
        `${u.id.padEnd(16)} ${u.role.padEnd(7)} ${u.disabled ? "nonaktif" : u.password_hash ? "aktif   " : "tanpa-pw"} ${u.name}`,
      );
    }
    for (const w of cfg.warnings) console.log(`! ${w}`);
    break;
  }
  case "user-add": {
    const id = (args[0] || "").toLowerCase();
    if (!validId(id)) die("Pakai: user-add <id> [--name \"Nama\"] [--role admin|tester]  (id: huruf kecil, angka, . _ -)");
    const role = flag("role") || "tester";
    if (role !== "admin" && role !== "tester") die("Role harus admin atau tester.");
    const lines = readLines();
    if (userRange(lines, id)) die(`User "${id}" sudah ada. Ganti password dengan: make passwd U=${id}`);
    const hash = await newHash();
    let { start, end } = usersBlock(lines);
    if (start < 0) {
      lines.push("", "users:");
      start = lines.length - 1;
      end = lines.length;
    } else if (/^users:\s*\{\s*\}/.test(lines[start])) {
      lines[start] = "users:";
    }
    let at = end;
    while (at > start + 1 && lines[at - 1].trim() === "") at--;
    lines.splice(at, 0, `  ${id}:`, `    name: ${yamlString(flag("name") || id)}`, `    role: ${role}`, `    password_hash: ${yamlString(hash)}`);
    save(lines);
    console.log(`User "${id}" (${role}) ditambahkan ke ${CONFIG}.`);
    break;
  }
  case "passwd": {
    const id = (args[0] || "").toLowerCase();
    const lines = readLines();
    if (!userRange(lines, id)) die(`User "${id}" tidak ada.`);
    setField(lines, id, "password_hash", yamlString(await newHash()));
    save(lines);
    console.log(`Password "${id}" diganti. Semua sesi user ini otomatis keluar.`);
    break;
  }
  case "user-rm": {
    const id = (args[0] || "").toLowerCase();
    const lines = readLines();
    const r = userRange(lines, id);
    if (!r) die(`User "${id}" tidak ada.`);
    lines.splice(r.from, r.to - r.from);
    save(lines);
    console.log(`User "${id}" dihapus. Progres tesnya tetap tersimpan di state.`);
    break;
  }
  case "user-disable":
  case "user-enable": {
    const id = (args[0] || "").toLowerCase();
    const lines = readLines();
    setField(lines, id, "disabled", cmd === "user-disable" ? "true" : null);
    save(lines);
    console.log(`User "${id}" ${cmd === "user-disable" ? "dinonaktifkan" : "diaktifkan"}.`);
    break;
  }
  case "check": {
    const cfg = loadConfigFile(CONFIG);
    console.log(`OK: ${Object.keys(cfg.users).length} user, docs.dir=${cfg.docs.dir}, url=${cfg.server.public_url || "-"}`);
    for (const w of cfg.warnings) console.log(`! ${w}`);
    break;
  }
  default:
    console.error("Perintah: hash | users | user-add <id> | passwd <id> | user-rm <id> | user-disable <id> | user-enable <id> | check");
    process.exit(2);
}
