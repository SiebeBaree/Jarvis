import { createHash, timingSafeEqual } from "node:crypto";

/**
 * Constant-time comparison of a presented bearer token against an expected
 * secret. Both values are SHA-256 digested first so the buffers always have
 * equal length (32 bytes), keeping `timingSafeEqual` from throwing and from
 * leaking length information.
 */
function tokenMatches(presented: string, expected: string): boolean {
  const a = createHash("sha256").update(presented).digest();
  const b = createHash("sha256").update(expected).digest();
  return timingSafeEqual(a, b);
}

function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (!header) return null;
  const match = /^Bearer (.+)$/.exec(header);
  return match ? match[1] : null;
}

function unauthorized(): Response {
  return Response.json({ error: "unauthorized" }, { status: 401 });
}

/**
 * Validates the `Authorization: Bearer <token>` header against
 * `process.env.API_TOKEN`. Returns a 401 JSON `Response` when missing or
 * invalid, or `null` when authorized.
 */
export function requireAuth(req: Request): Response | null {
  const expected = process.env.API_TOKEN;
  const presented = bearerToken(req);
  if (!expected || !presented || !tokenMatches(presented, expected)) {
    return unauthorized();
  }
  return null;
}

/**
 * Validates the `Authorization: Bearer <token>` header against
 * `process.env.CRON_SECRET` for cron-only routes. Returns a 401 JSON
 * `Response` when missing or invalid, or `null` when authorized.
 */
export function requireCron(req: Request): Response | null {
  const expected = process.env.CRON_SECRET;
  const presented = bearerToken(req);
  if (!expected || !presented || !tokenMatches(presented, expected)) {
    return unauthorized();
  }
  return null;
}
