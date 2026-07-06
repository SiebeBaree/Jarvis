import { SettingsPatchSchema, type Settings } from "@jarvis/shared";
import { eq } from "drizzle-orm";
import { HttpError, json, parseBody } from "@/lib/api";
import { requireAuth } from "@/lib/auth";
import { db } from "@/db";
import { settings, type SettingsRow } from "@/db/schema";

const SINGLETON_ID = 1;

function toSettings(row: SettingsRow): Settings {
  return {
    timezone: row.timezone,
    dayEndsAt: row.dayEndsAt,
    expoPushToken: row.expoPushToken,
    morningBriefingAt: row.morningBriefingAt,
    eveningReviewAt: row.eveningReviewAt,
    coachModel: row.coachModel,
  };
}

/** Reads the singleton settings row, creating it with defaults on first read. */
async function getOrCreateSettings(): Promise<SettingsRow> {
  const existing = await db
    .select()
    .from(settings)
    .where(eq(settings.id, SINGLETON_ID))
    .limit(1);
  if (existing[0]) return existing[0];

  const inserted = await db
    .insert(settings)
    .values({ id: SINGLETON_ID })
    .onConflictDoNothing()
    .returning();
  if (inserted[0]) return inserted[0];

  // Lost the insert race: another request created it first.
  const row = await db
    .select()
    .from(settings)
    .where(eq(settings.id, SINGLETON_ID))
    .limit(1);
  if (!row[0]) throw new Error("failed to load settings singleton");
  return row[0];
}

export async function GET(req: Request): Promise<Response> {
  const unauthorized = requireAuth(req);
  if (unauthorized) return unauthorized;

  const row = await getOrCreateSettings();
  return json(toSettings(row));
}

export async function PATCH(req: Request): Promise<Response> {
  const unauthorized = requireAuth(req);
  if (unauthorized) return unauthorized;

  try {
    const patch = await parseBody(req, SettingsPatchSchema);

    // Ensure the singleton exists before updating.
    await getOrCreateSettings();

    const updated = await db
      .update(settings)
      .set({ ...patch, updatedAt: new Date() })
      .where(eq(settings.id, SINGLETON_ID))
      .returning();

    const row = updated[0];
    if (!row) throw new Error("failed to update settings singleton");
    return json(toSettings(row));
  } catch (err) {
    if (err instanceof HttpError) return err.response;
    throw err;
  }
}
