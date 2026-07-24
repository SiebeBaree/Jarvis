// Evening wrap-up: fast-tier, generated lazily on request and cached per
// dayKey. Regenerates when the day materially changed (fingerprint of open
// items + score). No cron — opening the app is the trigger.
//
// The morning briefing was removed (docs/deviations.md): it fired an LLM call
// on every Today load, which dominated the screen's latency.

import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { briefings, dailyScores } from "@/db/schema";
import type { SettingsRow } from "../auth";
import { addDays } from "../daykey";
import { todayKey } from "../scoring/snapshot";
import { buildDayPayload, type DayPayload } from "../today";
import { callModel } from "./provider";

export interface BriefingRow {
  dayKey: string;
  kind: "morning" | "wrapup";
  content: string;
  createdAt: Date;
}

function wrapupFingerprint(payload: DayPayload): string {
  const openTasks = payload.tasksDue.filter((t) => t.status === "open").length;
  const habitsDone = payload.habits.filter((h) => h.credit >= 1).length;
  return `${openTasks}:${habitsDone}:${payload.mood?.value ?? "x"}:${Math.round(payload.score.total ?? -1)}`;
}

const WRAPUP_INSTRUCTIONS = `You are J.A.R.V.I.S. writing a one-sentence evening wrap-up. Calm and literal, no exclamation marks. State where the day stands and, if anything meaningful is still open, name the single most worthwhile remaining item ("Strong day — 2 tasks left if you want the sweep."). One sentence only.`;

export async function getWrapup(userId: string, settings: SettingsRow): Promise<BriefingRow> {
  const kind = "wrapup" as const;
  const dayKey = todayKey(settings);
  const payload = await buildDayPayload(userId, settings, dayKey, { isToday: false });
  const fingerprint = wrapupFingerprint(payload);

  const existing = await db.query.briefings.findFirst({
    where: and(eq(briefings.userId, userId), eq(briefings.dayKey, dayKey), eq(briefings.kind, kind)),
  });
  if (existing && existing.fingerprint === fingerprint) return existing;

  const yesterday = await db.query.dailyScores.findFirst({
    where: and(eq(dailyScores.userId, userId), eq(dailyScores.dayKey, addDays(dayKey, -1))),
  });

  const input = JSON.stringify({
    today: {
      dayKey,
      weekNumber: payload.weekNumber,
      isReviewWeek: payload.isReviewWeek,
      score: payload.score.total,
      mood: payload.mood?.value ?? null,
      tasks: payload.tasksDue.map((t) => ({ title: t.title, status: t.status, priority: t.priority })),
      overdue: payload.overdueTasks.map((t) => t.title),
      habits: payload.habits.map((h) => ({
        name: h.habit.name,
        type: h.habit.type,
        repsToday: h.repsToday,
        weekTotal: h.weekTotal,
        target: h.habit.targetReps,
        pace: h.pace?.kind ?? null,
      })),
    },
    yesterdayScore: yesterday?.total ?? null,
  });

  const call = await callModel({
    task: "briefing",
    instructions: WRAPUP_INSTRUCTIONS,
    input,
    maxOutputTokens: 2000,
  });
  const content = call.text.trim();

  const [row] = await db
    .insert(briefings)
    .values({ userId, dayKey, kind, content, fingerprint, model: call.model })
    .onConflictDoUpdate({
      target: [briefings.userId, briefings.dayKey, briefings.kind],
      set: { content, fingerprint, model: call.model, createdAt: new Date() },
    })
    .returning();
  return row!;
}
