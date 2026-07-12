// AI commentary on improvement-area photo check-ins: compares this week's
// photo against previous weeks and writes concrete observations. Runs after
// the upload response via next/server `after()` — best-effort, never blocks
// or fails the upload.

import { and, desc, eq, lt } from "drizzle-orm";
import { db } from "@/db/client";
import { areaCheckins, improvementAreas, type AiOverrides } from "@/db/schema";
import { callModel } from "./provider";

const PREVIOUS_PHOTOS = 4;
const SIGNED_URL_TTL_MS = 15 * 60 * 1000; // model fetches promptly; keep it short

const COMMENTARY_INSTRUCTIONS = `You are J.A.R.V.I.S., reviewing the user's weekly photo check-in for one self-improvement area. Calm, dry, precise, quietly loyal — no exclamation marks, no cheerleading. The user is autistic; be literal and concrete, never vague.

You get THIS week's photo first, then previous weeks' photos (each labeled with its week). Write:
- 2-4 concrete observations comparing this week to the previous photos (what changed, what did not).
- At most 2 specific, actionable suggestions for the coming week, tied to what the area's "better looks like" says.
If this is the first photo, describe the baseline honestly and name the 1-2 things most worth working on.
Plain prose, no headings, no lists, no emoji. Maximum ~120 words. Never comment on anything outside the stated area.`;

export async function generateCheckinCommentary(
  userId: string,
  checkinId: string,
  overrides: AiOverrides,
): Promise<void> {
  try {
    const checkin = await db.query.areaCheckins.findFirst({
      where: and(eq(areaCheckins.id, checkinId), eq(areaCheckins.userId, userId)),
    });
    if (!checkin) return;
    const area = await db.query.improvementAreas.findFirst({
      where: eq(improvementAreas.id, checkin.areaId),
    });
    if (!area) return;

    const previous = await db.query.areaCheckins.findMany({
      where: and(
        eq(areaCheckins.areaId, checkin.areaId),
        lt(areaCheckins.weekKey, checkin.weekKey),
      ),
      orderBy: [desc(areaCheckins.weekKey)],
      limit: PREVIOUS_PHOTOS,
    });

    if (!process.env.BLOB_READ_WRITE_TOKEN) {
      console.error("Check-in commentary skipped: BLOB_READ_WRITE_TOKEN not set");
      return;
    }
    const { issueSignedToken, presignUrl } = await import("@vercel/blob");
    const token = await issueSignedToken({
      pathname: "*",
      operations: ["get"],
      validUntil: Date.now() + SIGNED_URL_TTL_MS,
    });
    const presign = async (pathname: string) =>
      (await presignUrl(token, { operation: "get", pathname, access: "private" })).presignedUrl;

    const content: Record<string, unknown>[] = [
      {
        type: "input_text",
        text: JSON.stringify({
          area: area.name,
          betterLooksLike: area.betterLooksLike ?? "not specified",
          thisWeek: checkin.weekKey,
          previousWeeks: previous.map((p) => p.weekKey),
        }),
      },
      { type: "input_text", text: `THIS week (${checkin.weekKey}):` },
      { type: "input_image", image_url: await presign(checkin.blobKey), detail: "high" },
    ];
    for (const prev of previous) {
      content.push({ type: "input_text", text: `Previous week (${prev.weekKey}):` });
      content.push({ type: "input_image", image_url: await presign(prev.blobKey), detail: "high" });
    }

    const call = await callModel({
      task: "checkin_commentary",
      instructions: COMMENTARY_INSTRUCTIONS,
      input: [{ role: "user", content }],
      overrides,
      maxOutputTokens: 4000,
    });
    const commentary = call.text.trim();
    if (!commentary) return;

    await db
      .update(areaCheckins)
      .set({ aiCommentary: commentary, aiModel: call.model, aiGeneratedAt: new Date() })
      .where(eq(areaCheckins.id, checkinId));
  } catch (error) {
    console.error("Check-in commentary failed (ignored):", error);
  }
}
