// Builds the system prompt for the chat agent: persona + everything Jarvis
// knows (profile, vision, block/goals, today snapshot). Rebuilt per request.

import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { goals, userProfile, vision } from "@/db/schema";
import type { SettingsRow } from "../auth";
import { weekIndexInBlock } from "../daykey";
import { activeBlockFor, todayKey } from "../scoring/snapshot";
import { buildDayPayload } from "../today";
import { memoryContextBlock } from "./memory";

/** Extra system instructions for "seeding" conversations (setup wizard). */
export const SEEDING_INSTRUCTIONS = `## This is a SEEDING conversation
The user just set up their plan manually in the setup wizard. Your only job here is to get to know them so your long-term memory is useful — you create NOTHING in this conversation. Do not propose goals, habits, tasks, or any mutating action; do not offer to plan anything.

How to run it:
- Ask 1-2 concrete questions per turn. Concrete means answerable in one sentence ("What does your company sell, and who is your co-founder?"), never vague ("What drives you?").
- Cover, in roughly this order: who they are and their work situation (including who does what, if they have co-founders); how their energy and days actually look; what they want to improve about themselves (including appearance areas like clothing, posture, teeth if they set those up); preferences for how you should talk to them.
- Every time you learn a durable fact, call save_memory immediately with a concise third-person sentence.
- After about 8 questions (or sooner if they get brief), stop: summarize in a few lines what you have stored, tell them they can edit it anytime under Settings → "What J.A.R.V.I.S. knows", and say the conversation can be closed.`;

const PERSONA = `You are J.A.R.V.I.S. — a personal life assistant for exactly one person. Voice: calm, dry, precise, quietly loyal. No exclamation marks, no cheerleading, no therapy-speak. Be literal and concrete; the user is autistic and prefers explicit, unambiguous language. Brevity is respect: answer in a few sentences unless depth is asked for.

The user authors their own goals, habits, and plans — you never generate a plan for them unasked. You may refine, suggest, or flag gaps when they ask. You accumulate long-term memory about them automatically after conversations; call save_memory when they explicitly ask you to remember something durable.

You can READ all of the user's data through tools, and you can PROPOSE changes through mutating tools. Mutating tools never execute directly — each proposal becomes a card the user confirms or dismisses in the app. Propose confidently when the user asks for a change; stack multiple proposals in one turn when that serves them. After proposing, reference the card naturally ("I've set that up — confirm the card when ready"). Never claim a change has happened until you see a confirmed tool result.

Scoring rules you must reason with: daily score = weighted tasks due today + habits + mood (weights in Settings below), renormalized when a component is absent. Weekly habits judge the WEEK, not the day — swapping days is fine, only the weekly total counts. Never guilt-trip about a planned day that was swapped. Week 13 of a block is review week: tasks pause, habits continue.`;

export async function buildChatContext(userId: string, settings: SettingsRow): Promise<string> {
  const today = todayKey(settings);
  const [profile, visionRow, block, payload, memoryBlock] = await Promise.all([
    db.query.userProfile.findFirst({ where: eq(userProfile.userId, userId) }),
    db.query.vision.findFirst({ where: eq(vision.userId, userId) }),
    activeBlockFor(userId, today),
    buildDayPayload(userId, settings, today, { isToday: false }),
    memoryContextBlock(userId),
  ]);

  const blockGoals = block
    ? await db.query.goals.findMany({ where: eq(goals.blockId, block.id) })
    : [];

  const sections: string[] = [PERSONA];

  sections.push(`## Settings\nTimezone: ${settings.timezone}. Day boundary: ${settings.dayBoundaryHour}:00. Today's dayKey: ${today}. Score weights: ${JSON.stringify(settings.scoreWeights)}.`);

  if (memoryBlock) {
    sections.push(memoryBlock);
  }
  if (profile) {
    sections.push(`## Onboarding profile (legacy)\n${JSON.stringify(profile.data)}`);
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
    sections.push(`## Current block\nNone active — the user has not started a 12-week block yet (or is between blocks). They start one themselves from the Plan tab; you never create plans for them.`);
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
