import { describe, expect, it } from "vitest";
import worker, { takeRateLimits, validateEvent, type Env } from "../src/index";

const validEvent = {
  schema_version: 1,
  event: "install",
  installation_id: "0123456789abcdef0123456789abcdef",
  version: "1.24.0",
  os: "debian",
  arch: "x86_64",
};

function request(body: string, headers: HeadersInit = { "Content-Type": "application/json" }): Request {
  return new Request("https://telemetry.example/v1/event", { method: "POST", headers, body });
}

interface LimitRow {
  subject_hash: string;
  bucket: number;
  count: number;
  expires_at: number;
}

class RateLimitDatabase {
  readonly rows = new Map<string, LimitRow>();

  prepare(query: string): D1PreparedStatement {
    expect(query).toContain("WITH subjects(subject_hash, max_count)");
    return {
      bind: (...values: unknown[]) => ({
        run: async () => {
          const [installationHash, installationLimit, sourceHash, sourceLimit, bucket, expiresAt, lookupBucket] = values as [
            string, number, string, number, number, number, number,
          ];
          expect(lookupBucket).toBe(bucket);
          const subjects = [
            { subjectHash: installationHash, limit: installationLimit },
            { subjectHash: sourceHash, limit: sourceLimit },
          ];
          const blocked = subjects.some(({ subjectHash, limit }) =>
            (this.rows.get(`${subjectHash}:${bucket}`)?.count ?? 0) >= limit,
          );
          if (blocked) return { meta: { changes: 0 } };
          for (const { subjectHash } of subjects) {
            const key = `${subjectHash}:${bucket}`;
            const current = this.rows.get(key);
            this.rows.set(key, {
              subject_hash: subjectHash,
              bucket,
              count: (current?.count ?? 0) + 1,
              expires_at: expiresAt,
            });
          }
          return { meta: { changes: 2 } };
        },
      }),
    } as unknown as D1PreparedStatement;
  }

  setCount(subjectHash: string, now: number, count: number): void {
    const bucket = Math.floor(now / 3600);
    this.rows.set(`${subjectHash}:${bucket}`, {
      subject_hash: subjectHash,
      bucket,
      count,
      expires_at: (bucket + 2) * 3600,
    });
  }

  count(subjectHash: string, now: number): number {
    return this.rows.get(`${subjectHash}:${Math.floor(now / 3600)}`)?.count ?? 0;
  }
}

describe("event schema", () => {
  it("accepts only the exact schema and whitelist", () => {
    expect(validateEvent(validEvent)).not.toBeNull();
    expect(validateEvent({ ...validEvent, event: "command" })).toBeNull();
    expect(validateEvent({ ...validEvent, extra: true })).toBeNull();
    expect(validateEvent({ ...validEvent, installation_id: "device-1" })).toBeNull();
    expect(validateEvent({ ...validEvent, version: `1.${"9".repeat(4000)}.0` })).toBeNull();
    expect(validateEvent({ ...validEvent, version: "1.24.0" })).not.toBeNull();
  });
});

describe("atomic dual rate limit", () => {
  const now = 1_700_000_000;
  const installation = "installation:test-installation";
  const source = "source:test-source";

  it("increments both counters when both quotas allow the request", async () => {
    const db = new RateLimitDatabase();

    await expect(takeRateLimits(db as unknown as D1Database, "test-installation", "test-source", now)).resolves.toBe(true);
    expect(db.count(installation, now)).toBe(1);
    expect(db.count(source, now)).toBe(1);
  });

  it("does not consume source quota when installation quota rejects", async () => {
    const db = new RateLimitDatabase();
    db.setCount(installation, now, 30);
    db.setCount(source, now, 7);

    await expect(takeRateLimits(db as unknown as D1Database, "test-installation", "test-source", now)).resolves.toBe(false);
    expect(db.count(installation, now)).toBe(30);
    expect(db.count(source, now)).toBe(7);
  });

  it("does not consume installation quota when source quota rejects", async () => {
    const db = new RateLimitDatabase();
    db.setCount(installation, now, 7);
    db.setCount(source, now, 120);

    await expect(takeRateLimits(db as unknown as D1Database, "test-installation", "test-source", now)).resolves.toBe(false);
    expect(db.count(installation, now)).toBe(7);
    expect(db.count(source, now)).toBe(120);
  });
});

describe("HTTP boundary", () => {
  const unusedEnv = { TELEMETRY_HMAC_KEY: "x".repeat(32) } as Env;

  it("rejects the wrong content type before touching D1", async () => {
    const response = await worker.fetch(request(JSON.stringify(validEvent), { "Content-Type": "text/plain" }), unusedEnv);
    expect(response.status).toBe(415);
  });

  it("rejects malformed and oversized JSON before touching D1", async () => {
    expect((await worker.fetch(request("{"), unusedEnv)).status).toBe(400);
    expect((await worker.fetch(request(`{"padding":"${"x".repeat(4096)}"}`), unusedEnv)).status).toBe(413);
  });

  it("caps an oversized body that carries no Content-Length", async () => {
    const encoded = new TextEncoder().encode("x".repeat(8192));
    let pushed = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (pushed > 1 << 20) {
          controller.close();
          return;
        }
        pushed += encoded.byteLength;
        controller.enqueue(encoded);
      },
    });
    const chunked = new Request("https://telemetry.example/v1/event", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      duplex: "half",
    } as RequestInit & { duplex: "half" });
    // 前置条件本身也要成立：没有 Content-Length，声明式头检会被跳过
    expect(chunked.headers.get("Content-Length")).toBe(null);
    expect((await worker.fetch(chunked, unusedEnv)).status).toBe(413);
    // 判别性断言：先缓冲再判大的实现会把整条流吸完（>1 MiB），带上限的读取只会越过上限一块就停
    expect(pushed).toBeLessThanOrEqual(2 * encoded.byteLength);
  });

  it("serves browser cross-origin reads but refuses browser writes", async () => {
    const preflight = await worker.fetch(
      new Request("https://telemetry.example/v1/public/summary", { method: "OPTIONS" }),
      unusedEnv,
    );
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(preflight.headers.get("Access-Control-Allow-Methods")).not.toContain("POST");

    const eventPreflight = await worker.fetch(
      new Request("https://telemetry.example/v1/event", { method: "OPTIONS" }),
      unusedEnv,
    );
    expect(eventPreflight.headers.get("Access-Control-Allow-Origin")).toBe(null);
    expect((await worker.fetch(request(JSON.stringify(validEvent), { "Content-Type": "application/json", Origin: "https://evil.example" }), unusedEnv)).status).toBe(403);
    const writeResponse = await worker.fetch(request(JSON.stringify(validEvent), { "Content-Type": "text/plain" }), unusedEnv);
    expect(writeResponse.status).toBe(415);
    expect(writeResponse.headers.get("Access-Control-Allow-Origin")).toBe(null);
  });
});
