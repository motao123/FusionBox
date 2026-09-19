export interface Env {
  DB: D1Database;
  TELEMETRY_HMAC_KEY: string;
}

const MAX_BODY_BYTES = 4096;
const CACHE_SECONDS = 300;
const INSTALLATION_LIMIT = 30;
const IP_LIMIT = 120;
const EVENTS = ["install", "update", "uninstall", "heartbeat"] as const;
const OPERATING_SYSTEMS = [
  "debian", "ubuntu", "centos", "rocky", "almalinux", "fedora", "arch", "other",
] as const;
const ARCHITECTURES = ["x86_64", "aarch64", "armv7l", "other"] as const;
const FIELDS = ["schema_version", "event", "installation_id", "version", "os", "arch"] as const;

type EventName = (typeof EVENTS)[number];
interface TelemetryEvent {
  schema_version: 1;
  event: EventName;
  installation_id: string;
  version: string;
  os: (typeof OPERATING_SYSTEMS)[number];
  arch: (typeof ARCHITECTURES)[number];
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function json(data: unknown, status = 200, extraHeaders: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders,
    },
  });
}

function isOneOf<T extends readonly string[]>(value: unknown, values: T): value is T[number] {
  return typeof value === "string" && values.includes(value);
}

export function validateEvent(value: unknown): TelemetryEvent | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);
  if (keys.length !== FIELDS.length || keys.some((key) => !FIELDS.includes(key as typeof FIELDS[number]))) {
    return null;
  }
  if (input.schema_version !== 1 || !isOneOf(input.event, EVENTS)) return null;
  if (typeof input.installation_id !== "string" || !/^[0-9a-f]{32}$/i.test(input.installation_id)) return null;
  if (typeof input.version !== "string" || !/^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]{1,32})?$/.test(input.version)) return null;
  if (!isOneOf(input.os, OPERATING_SYSTEMS) || !isOneOf(input.arch, ARCHITECTURES)) return null;
  return input as unknown as TelemetryEvent;
}

async function hmac(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function readBody(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("Content-Length");
  if (declaredLength !== null && (!/^\d+$/.test(declaredLength) || Number(declaredLength) > MAX_BODY_BYTES)) {
    throw new Response(null, { status: 413 });
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_BODY_BYTES) throw new Response(null, { status: 413 });
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    throw new Response(null, { status: 400 });
  }
}

export async function takeRateLimits(
  db: D1Database,
  installationHash: string,
  sourceHash: string,
  now: number,
): Promise<boolean> {
  const bucket = Math.floor(now / 3600);
  const result = await db.prepare(
    `WITH subjects(subject_hash, max_count) AS (
       VALUES (?, ?), (?, ?)
     )
     INSERT INTO rate_limits (subject_hash, bucket, count, expires_at)
     SELECT subject_hash, ?, 1, ?
     FROM subjects
     WHERE NOT EXISTS (
       SELECT 1
       FROM subjects AS candidate
       JOIN rate_limits AS current
         ON current.subject_hash = candidate.subject_hash
        AND current.bucket = ?
       WHERE current.count >= candidate.max_count
     )
     ON CONFLICT (subject_hash, bucket) DO UPDATE SET
       count = rate_limits.count + 1,
       expires_at = excluded.expires_at`,
  ).bind(
    `installation:${installationHash}`,
    INSTALLATION_LIMIT,
    `source:${sourceHash}`,
    IP_LIMIT,
    bucket,
    (bucket + 2) * 3600,
    bucket,
  ).run();
  return result.meta.changes === 2;
}

async function acceptEvent(request: Request, env: Env): Promise<Response> {
  if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) {
    return json({ error: "content_type_must_be_application_json" }, 415);
  }
  if (!env.TELEMETRY_HMAC_KEY || env.TELEMETRY_HMAC_KEY.length < 32) {
    return json({ error: "service_misconfigured" }, 503);
  }

  let parsed: unknown;
  try {
    parsed = await readBody(request);
  } catch (error) {
    if (error instanceof Response) return json({ error: error.status === 413 ? "body_too_large" : "invalid_json" }, error.status);
    throw error;
  }
  const event = validateEvent(parsed);
  if (!event) return json({ error: "invalid_event" }, 400);

  const now = Math.floor(Date.now() / 1000);
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  const installationHash = await hmac(env.TELEMETRY_HMAC_KEY, `installation:${event.installation_id.toLowerCase()}`);
  const source = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const sourceHash = await hmac(env.TELEMETRY_HMAC_KEY, `source:${source}`);

  if (!await takeRateLimits(env.DB, installationHash, sourceHash, now)) {
    return json({ error: "rate_limited" }, 429, { "Retry-After": "3600" });
  }

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO daily_events (day, event, version, os, arch, count)
       VALUES (?, ?, ?, ?, ?, 1)
       ON CONFLICT (day, event, version, os, arch) DO UPDATE SET count = count + 1`,
    ).bind(day, event.event, event.version, event.os, event.arch),
    env.DB.prepare(
      `INSERT INTO installations (installation_hash, first_seen_day, last_seen_day)
       VALUES (?, ?, ?)
       ON CONFLICT (installation_hash) DO UPDATE SET last_seen_day = excluded.last_seen_day`,
    ).bind(installationHash, day, day),
  ]);

  if (Math.random() < 0.01) {
    await env.DB.prepare("DELETE FROM rate_limits WHERE expires_at < ?").bind(now).run();
  }
  return json({ accepted: true }, 202, { "Cache-Control": "no-store" });
}

interface SummaryRow {
  events_30d: number;
  installations_total: number;
  installations_active_30d: number;
  generated_at: string;
}

async function buildSummary(db: D1Database): Promise<SummaryRow> {
  const cutoff = new Date(Date.now() - 29 * 86400000).toISOString().slice(0, 10);
  const [events, installations] = await db.batch([
    db.prepare("SELECT COALESCE(SUM(count), 0) AS events_30d FROM daily_events WHERE day >= ?").bind(cutoff),
    db.prepare(
      `SELECT COUNT(*) AS installations_total,
       COALESCE(SUM(CASE WHEN last_seen_day >= ? THEN 1 ELSE 0 END), 0) AS installations_active_30d
       FROM installations`,
    ).bind(cutoff),
  ]);
  const eventRow = events.results[0] as { events_30d?: number } | undefined;
  const installationRow = installations.results[0] as { installations_total?: number; installations_active_30d?: number } | undefined;
  return {
    events_30d: Number(eventRow?.events_30d ?? 0),
    installations_total: Number(installationRow?.installations_total ?? 0),
    installations_active_30d: Number(installationRow?.installations_active_30d ?? 0),
    generated_at: new Date().toISOString(),
  };
}

async function cachedPublic(request: Request, env: Env, badge: boolean): Promise<Response> {
  const cache = caches.default;
  const cacheKey = new Request(request.url, { method: "GET" });
  const hit = await cache.match(cacheKey);
  if (hit) return hit;

  const summary = await buildSummary(env.DB);
  let response: Response;
  if (badge) {
    const value = summary.installations_active_30d.toLocaleString("en-US");
    const label = "active installs";
    const labelWidth = 92;
    const valueWidth = Math.max(48, value.length * 8 + 16);
    const width = labelWidth + valueWidth;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="20" role="img" aria-label="${label}: ${value}"><title>${label}: ${value}</title><linearGradient id="s" x2="0" y2="100%"><stop offset="0" stop-color="#fff" stop-opacity=".7"/><stop offset=".1" stop-opacity=".1"/><stop offset=".9" stop-opacity=".3"/><stop offset="1" stop-opacity=".5"/></linearGradient><clipPath id="r"><rect width="${width}" height="20" rx="3"/></clipPath><g clip-path="url(#r)"><rect width="${labelWidth}" height="20" fill="#555"/><rect x="${labelWidth}" width="${valueWidth}" height="20" fill="#16803a"/><rect width="${width}" height="20" fill="url(#s)"/></g><g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,sans-serif" font-size="11"><text x="${labelWidth / 2}" y="15">${label}</text><text x="${labelWidth + valueWidth / 2}" y="15">${value}</text></g></svg>`;
    response = new Response(svg, { headers: { ...corsHeaders, "Content-Type": "image/svg+xml; charset=utf-8", "X-Content-Type-Options": "nosniff", "Cache-Control": `public, max-age=${CACHE_SECONDS}` } });
  } else {
    response = json(summary, 200, { "Cache-Control": `public, max-age=${CACHE_SECONDS}` });
  }
  await cache.put(cacheKey, response.clone());
  return response;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
    if (url.pathname === "/v1/event" && request.method === "POST") return acceptEvent(request, env);
    if (url.pathname === "/v1/public/summary" && request.method === "GET") return cachedPublic(request, env, false);
    if (url.pathname === "/v1/public/badge" && request.method === "GET") return cachedPublic(request, env, true);
    return json({ error: "not_found" }, 404);
  },
};
