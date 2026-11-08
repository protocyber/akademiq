// hub.yaml loader. Compose-style: ${VAR}, ${VAR:-default}, $$ for a literal $.
// Variables come from the process environment and, when present, a `.env`
// file next to hub.yaml (handy for secrets you do not want in the YAML).

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

export type Role = "admin" | "tester";

export type HubUser = {
  id: string;
  name: string;
  role: Role;
  password_hash: string;
  disabled: boolean;
};

export type HubConfig = {
  server: { title: string; port: number; public_url: string; timezone: string };
  docs: { dir: string };
  users: Record<string, HubUser>;
  warnings: string[];
};

const USER_ID = /^[a-z0-9][a-z0-9._-]{0,31}$/;

function readDotEnv(file: string): Record<string, string> {
  if (!existsSync(file)) return {};
  const out: Record<string, string> = {};
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!m) continue;
    let v = m[2];
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}

export function interpolate(text: string, env: Record<string, string | undefined>): string {
  return text.replace(/\$\$|\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:?-)([^}]*))?\}/g, (whole, name, op, def) => {
    if (whole === "$$") return "$";
    const v = env[name];
    if (op === ":-") return v ? v : (def ?? "");
    if (op === "-") return v !== undefined ? v : (def ?? "");
    return v ?? "";
  });
}

export function parseConfig(text: string, env: Record<string, string | undefined>): HubConfig {
  const doc = (Bun.YAML.parse(interpolate(text, env)) ?? {}) as any;
  const warnings: string[] = [];
  const server = doc.server ?? {};
  const users: Record<string, HubUser> = {};

  const rawUsers = doc.users ?? {};
  if (typeof rawUsers !== "object" || Array.isArray(rawUsers)) throw new Error("`users` must be a mapping of user id → settings");
  for (const [rawId, raw] of Object.entries<any>(rawUsers)) {
    const id = rawId.toLowerCase();
    if (!USER_ID.test(id)) {
      warnings.push(`user "${rawId}" skipped: ids are lowercase letters, digits, . _ - (max 32)`);
      continue;
    }
    const u = raw ?? {};
    const role: Role = u.role === "admin" ? "admin" : "tester";
    if (u.role && u.role !== "admin" && u.role !== "tester") warnings.push(`user "${id}": unknown role "${u.role}", using tester`);
    const hash = typeof u.password_hash === "string" ? u.password_hash.trim() : "";
    if (!hash) warnings.push(`user "${id}" has no password_hash and cannot sign in (make user-add / make passwd)`);
    else if (!hash.startsWith("$argon2") && !hash.startsWith("$2")) warnings.push(`user "${id}": password_hash is not an argon2/bcrypt hash`);
    if (typeof u.password === "string") warnings.push(`user "${id}": plain \`password\` is ignored; store password_hash only`);
    users[id] = {
      id,
      name: String(u.name ?? id).slice(0, 80),
      role,
      password_hash: hash,
      disabled: u.disabled === true,
    };
  }
  if (!Object.values(users).some((u) => u.role === "admin" && !u.disabled)) warnings.push("no enabled admin user");

  return {
    server: {
      title: String(server.title ?? "Test Hub"),
      port: Number(server.port ?? 8090),
      public_url: String(server.public_url ?? ""),
      timezone: String(server.timezone ?? "Asia/Jakarta"),
    },
    docs: { dir: String(doc.docs?.dir ?? "docs/manual-tests") },
    users,
    warnings,
  };
}

export function loadConfigFile(path: string): HubConfig {
  const env = { ...readDotEnv(join(dirname(path), ".env")), ...process.env };
  return parseConfig(readFileSync(path, "utf8"), env);
}
