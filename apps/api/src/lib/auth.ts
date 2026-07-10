import { hash, verify } from "@node-rs/argon2";
import { createHash, randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { sessions, settings, users } from "@/db/schema";
import { ApiError } from "./http";

const PEPPER = process.env.AUTH_PEPPER ?? "";
if (!PEPPER) {
  console.warn(
    "AUTH_PEPPER is not set — password hashes created now will stop verifying if a pepper is added later.",
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

/** Validates the bearer token and loads the user's settings. Throws 401. */
export async function requireAuth(request: Request): Promise<AuthContext> {
  const header = request.headers.get("authorization");
  const rawToken = header?.startsWith("Bearer ") ? header.slice(7).trim() : null;
  if (!rawToken) throw new ApiError(401, "unauthorized", "Missing bearer token");

  const session = await db.query.sessions.findFirst({
    where: eq(sessions.tokenHash, hashToken(rawToken)),
  });
  if (!session || session.revokedAt) throw new ApiError(401, "unauthorized", "Invalid or revoked token");

  const user = await db.query.users.findFirst({ where: eq(users.id, session.userId) });
  if (!user) throw new ApiError(401, "unauthorized", "User no longer exists");

  // Touch lastUsedAt at most ~hourly to keep reads cheap.
  if (Date.now() - session.lastUsedAt.getTime() > 60 * 60 * 1000) {
    await db.update(sessions).set({ lastUsedAt: new Date() }).where(eq(sessions.id, session.id));
  }

  return {
    userId: user.id,
    email: user.email,
    settings: await getOrCreateSettings(user.id),
    rawToken,
  };
}
