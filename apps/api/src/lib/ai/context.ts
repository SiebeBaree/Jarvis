// Builds the system prompt for the chat agent: persona + everything Jarvis
// knows (profile, vision, block/goals, today snapshot). Rebuilt per request.

import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goals, userProfile, vision } from "@/db/schema";
import type { SettingsRow } from "../auth";
import { weekIndexInBlock } from "../daykey";
import { activeBlockFor, todayKey } from "../scoring/snapshot";
import { buildDayPayload } from "../today";

const PERSONA = `You are J.A.R.V.I.S. — a personal life assistant for exactly one person. Voice: calm, dry, precise, quietly loyal. No exclamation marks, no cheerleading, no therapy-speak. Be literal and concrete; the user is autistic and prefers explicit, unambiguous language. Brevity is respect: answer in a few sentences unless depth is asked for.

You can READ all of the user's data through tools, and you can PROPOSE changes through mutating tools. Mutating tools never execute directly — each proposal becomes a card the user confirms or dismisses in the app. Propose confidently when the user asks for a change; stack multiple proposals in one turn when that serves them. After proposing, reference the card naturally ("I've set that up — confirm the card when ready"). Never claim a change has happened until you see a confirmed tool result.

Scoring rules you must reason with: daily score = weighted tasks due today + habits + mood (weights in Settings below), renormalized when a component is absent. Weekly habits judge the WEEK, not the day — swapping days is fine, only the weekly total counts. Never guilt-trip about a planned day that was swapped. Week 13 of a block is review week: tasks pause, habits continue.`;

export async function buildChatContext(userId: string, settings: SettingsRow): Promise<string> {
  const today = todayKey(settings);
  const [profile, visionRow, block, payload] = await Promise.all([
    db.query.userProfile.findFirst({ where: eq(userProfile.userId, userId) }),
    db.query.vision.findFirst({ where: eq(vision.userId, userId) }),
    activeBlockFor(userId, today),
    buildDayPayload(userId, settings, today, { isToday: false }),
  ]);

  const blockGoals = block
    ? await db.query.goals.findMany({ where: eq(goals.blockId, block.id) })
    : [];

  const sections: string[] = [PERSONA];

  sections.push(`## Settings\nTimezone: ${settings.timezone}. Day boundary: ${settings.dayBoundaryHour}:00. Today's dayKey: ${today}. Score weights: ${JSON.stringify(settings.scoreWeights)}.`);

  if (profile) {
    sections.push(`## What you know about the user\n${JSON.stringify(profile.data)}`);
  }
  if (visionRow?.content) {
    sections.push(`## Their vision (dream life)\n${visionRow.content.slice(0, 1200)}`);
  }
  if (block) {
    const week = weekIndexInBlock(today, block.startDate);
    sections.push(
      `## Current block\n"${block.title}" (block ${block.number}), ${block.startDate} → ${block.endDate}. Today is week ${week}${week === 13 ? " — REVIEW WEEK (tasks paused)" : ""}.\nGoals: ${blockGoals.map((g) => `"${g.title}" [${g.trackStatus ?? "no status"}]`).join(", ") || "none"}.`,
    );
  } else {
    sections.push(`## Current block\nNone active — the user has not started a 12-week block yet (or is between blocks). Onboarding creates one.`);
  }

  const compactTasks = payload.tasksDue.map((t) => ({
    id: t.id,
    title: t.title,
    status: t.status,
    priority: t.priority,
    subtasks: t.subtasks.length,
  }));
  const compactOverdue = payload.overdueTasks.map((t) => ({ id: t.id, title: t.title, dueDate: t.dueDate }));
  const compactHabits = payload.habits.map((h) => ({
    id: h.habit.id,
    name: h.habit.name,
    type: h.habit.type,
    target: h.habit.targetReps,
    repsToday: h.repsToday,
    weekTotal: h.weekTotal,
    pace: h.pace?.kind ?? null,
  }));
  sections.push(
    `## Today snapshot (${today})\nScore: ${payload.score.total ?? "—"} (tasks ${payload.score.taskPoints ?? "n/a"}, habits ${payload.score.habitPoints ?? "n/a"}, feel ${payload.score.feelPoints ?? "n/a"}).\nMood: ${payload.mood ? payload.mood.value : "not set yet"}.\nTasks due: ${JSON.stringify(compactTasks)}\nOverdue: ${JSON.stringify(compactOverdue)}\nHabits: ${JSON.stringify(compactHabits)}`,
  );

  return sections.join("\n\n");
}
