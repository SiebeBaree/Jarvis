import { hash, verify } from "@node-rs/argon2";
import { createHash, randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { sessions, settings, users } from "@/db/schema";
import { ApiError } from "./http";

const PEPPER = process.env.AUTH_PEPPER ?? "";
if (!PEPPER) {
  console.warn(
    "AUTH_PEPPER is not set. Password hashes created now will stop verifying if a pepper is added later.",
  );
}

export async function hashPassword(password: string): Promise<string> {
  return hash(password + PEPPER);
}

export async function verifyPassword(passwordHash: string, password: string): Promise<boolean> {
  try {
    return await verify(passwordHash, password + PEPPER);
  } catch {
    return false;
  }
}

function hashToken(rawToken: string): string {
  return createHash("sha256").update(rawToken).digest("hex");
}

/** Creates a session and returns the raw bearer token (only shown once). */
export async function createSession(userId: string, deviceName: string | null): Promise<string> {
  const rawToken = randomBytes(32).toString("hex");
  await db.insert(sessions).values({ userId, tokenHash: hashToken(rawToken), deviceName });
  return rawToken;
}

export async function revokeSession(rawToken: string): Promise<void> {
  await db
    .update(sessions)
    .set({ revokedAt: new Date() })
    .where(eq(sessions.tokenHash, hashToken(rawToken)));
}

export type SettingsRow = typeof settings.$inferSelect;

export interface AuthContext {
  userId: string;
  email: string;
  settings: SettingsRow;
  rawToken: string;
}

export async function getOrCreateSettings(userId: string): Promise<SettingsRow> {
  const existing = await db.query.settings.findFirst({ where: eq(settings.userId, userId) });
  if (existing) return existing;
  const [created] = await db.insert(settings).values({ userId }).returning();
  if (!created) throw new ApiError(500, "internal_error", "Could not create settings");
  return created;
}

/**
 * Validates the bearer token and loads the user's settings. Throws 401.
 *
 * Session + user + settings come back in ONE joined query: this runs before
 * every single request, and over the Neon HTTP driver each extra `findFirst`
 * is a full network round-trip added to the user's latency.
 */
export async function requireAuth(request: Request): Promise<AuthContext> {
  const header = request.headers.get("authorization");
  const rawToken = header?.startsWith("Bearer ") ? header.slice(7).trim() : null;
  if (!rawToken) throw new ApiError(401, "unauthorized", "Missing bearer token");

  const [row] = await db
    .select({
      sessionId: sessions.id,
      revokedAt: sessions.revokedAt,
      lastUsedAt: sessions.lastUsedAt,
      userId: users.id,
      email: users.email,
      settings: settings,
    })
    .from(sessions)
    .innerJoin(users, eq(users.id, sessions.userId))
    .leftJoin(settings, eq(settings.userId, users.id))
    .where(eq(sessions.tokenHash, hashToken(rawToken)))
    .limit(1);

  if (!row || row.revokedAt) throw new ApiError(401, "unauthorized", "Invalid or revoked token");

  // Touch lastUsedAt at most ~hourly to keep reads cheap.
  if (Date.now() - row.lastUsedAt.getTime() > 60 * 60 * 1000) {
    await db.update(sessions).set({ lastUsedAt: new Date() }).where(eq(sessions.id, row.sessionId));
  }

  return {
    userId: row.userId,
    email: row.email,
    // Only pre-settings accounts (or a mid-signup crash) miss the row.
    settings: row.settings ?? (await getOrCreateSettings(row.userId)),
    rawToken,
  };
}
