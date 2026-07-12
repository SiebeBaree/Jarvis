# Jarvis Redesign Implementation Plan — "You author, AI knows you"

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline execution) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Jarvis from an app whose AI writes your life plan into an app where you author the plan and the AI's job is to know you (growing memory), watch you (weekly photo check-ins on improvement areas with AI commentary), and support you (chat/briefings) — with a full account reset to start clean.

**Architecture:** Keep the entire 12WY container (blocks/goals/tactics/habits/tasks/scoring 40-40-20/mood/trends) unchanged. Remove the AI interview→plan pipeline entirely. Add three new subsystems: (1) `memories` — row-per-fact AI memory, auto-extracted after every chat turn via Next.js `after()`, editable via CRUD endpoints and a Swift Memory screen; (2) `improvement_areas` + `area_checkins` — weekly photo check-ins on private Vercel Blob with async AI vision commentary; (3) a manual Setup Wizard (SwiftUI) + a plan-free "seeding" chat conversation kind that only saves memories. Plus `POST /account/reset`.

**Tech stack:** Next.js 16 App Router (`after()` for post-response work), Drizzle/Neon Postgres, OpenAI Responses API (`gpt-5.6-luna`, vision input for commentary), zod v4, Vercel Blob (private + presigned), SwiftUI (iOS 17+/macOS 14+, @Observable stores), JarvisAPI Swift package.

**Approved product decisions (from user interview, 2026-07-12):**
- User authors plans; AI may assist via existing chat confirm-cards, never generates a plan unasked.
- 12WY blocks + scoring stay exactly as-is. Mood stays one 0–100/day.
- Improvement areas (posture, clothing, teeth, …): weekly app-prompted check-in, **photo only**, AI compares vs previous photos and comments.
- AI memory: learns from every chat automatically; user can view/edit everything it knows.
- Onboarding v2 = manual setup wizard + optional plan-free seeding conversation.
- Full data reset (all domain data; keep account + settings).
- Out of scope: push notifications (in-app card only), web client, business integrations, scoring changes, Body-tab rebuild, check-ins affecting score.

---

## File map

**apps/api — create**
- `src/lib/ai/memory.ts` — memory extraction (model call + ops application), context block builder
- `src/lib/ai/checkin-commentary.ts` — vision comparison call, commentary persistence
- `src/lib/checkins.ts` — due-week logic + DTO builders (pure logic separated for unit tests)
- `src/app/api/v1/memories/route.ts` — GET list, POST create
- `src/app/api/v1/memories/[id]/route.ts` — PATCH, DELETE
- `src/app/api/v1/improvement-areas/route.ts` — GET (with due/thisWeek info), POST
- `src/app/api/v1/improvement-areas/[id]/route.ts` — PATCH (incl. archive), DELETE
- `src/app/api/v1/improvement-areas/[id]/checkins/route.ts` — GET timeline, POST photo bytes
- `src/app/api/v1/account/reset/route.ts` — POST full wipe
- `tests/checkins.test.ts`, `tests/memory.test.ts` — unit tests for due-week + op application + validation

**apps/api — modify**
- `src/db/schema.ts` — add `memories`, `improvementAreas`, `areaCheckins` tables; add `"seeding"` to `conversation_kind` enum; add `memorySource` enum
- `src/lib/validation.ts` — new schemas; delete `interviewStartSchema`
- `src/lib/ai/tiers.ts` — remove interview/plan tasks; add `memory_extraction: "fast"`, `checkin_commentary: "deep"`, `seeding: "chat"-tier ("fast")`
- `src/lib/ai/provider.ts` — `callModel` accepts structured (vision) input
- `src/lib/ai/context.ts` — memories section in system prompt; persona updated (user authors plans; block wording)
- `src/lib/ai/agent.ts` — third tool class: MEMORY tools execute inline (not confirm-cards)
- `src/lib/ai/tools.ts` — add `save_memory`, `list_memories` (inline), `get_improvement_areas` (read)
- `src/app/api/v1/ai/chat/route.ts` — accept `kind: "seeding"` for new conversations; seeding extraInstructions; `after()`-hook memory extraction on every turn
- `drizzle/0003_*.sql` — generated migration

**apps/api — delete**
- `src/lib/ai/interview.ts`, `src/lib/ai/apply-plan.ts`
- `src/app/api/v1/ai/interview/**` (5 routes)
- `tests/integration/interview.ai.test.ts`, `tests/integration/interview.e2e.test.ts`

**apps/app — create**
- `Jarvis/Features/Setup/SetupWizardView.swift` — paged wizard shell (welcome→areas→block→goals→habits→improve→seed→done)
- `Jarvis/Features/Setup/SetupWizardStore.swift` — wizard state + API calls
- `Jarvis/Features/Setup/SetupSteps.swift` — the step subviews
- `Jarvis/Features/Improve/ImproveStore.swift` — improvement areas + check-ins state
- `Jarvis/Features/Improve/ImproveView.swift` — areas list (due badges, thumbnails)
- `Jarvis/Features/Improve/ImprovementAreaDetailView.swift` — photo timeline + commentary
- `Jarvis/Features/Improve/CheckinFlowView.swift` — sequential per-area photo capture/pick + upload
- `Jarvis/Features/Improve/AreaEditorView.swift` — create/edit improvement area
- `Jarvis/Features/Today/CheckinPromptCard.swift` — weekly due card on Today
- `Jarvis/Features/Settings/MemoryView.swift` — grouped memory list, edit/delete/add
- `Packages/JarvisAPI/Sources/JarvisAPI/Endpoints+Memory.swift`, `Models+Memory.swift`
- `Packages/JarvisAPI/Sources/JarvisAPI/Endpoints+Improve.swift`, `Models+Improve.swift`
- `Packages/JarvisAPI/Tests/JarvisAPITests/MemoryImproveModelsTests.swift`

**apps/app — modify**
- `Jarvis/RootView.swift` — add `.improve` section (macOS sidebar Progress group; iPhone via Today toolbar); first-run → SetupWizard
- `Jarvis/AppModel.swift` — `needsFirstRunOnboarding` drives wizard now
- `Jarvis/Features/Today/TodayView.swift` + `TodayStore.swift` — check-in prompt card + Improve toolbar link
- `Jarvis/Features/Plan/PlanView.swift` (+ PlanStore) — replace interview entry points with wizard/manual creation
- `Jarvis/Features/Settings/SettingsView.swift` — Memory entry + Danger-zone reset
- `Jarvis/Features/Chat/ConversationListView.swift` — memory toolbar button
- `Packages/JarvisAPI/Sources/JarvisAPI/Endpoints+Plan.swift` — remove interview endpoints, add blocks create if missing; `Endpoints.swift` — reset endpoint
- `Packages/JarvisAPI/Sources/JarvisAPI/Endpoints+Chat.swift` — chat accepts kind for new conversation

**apps/app — delete**
- `Jarvis/Features/Onboarding/` (all 7 files), `Jarvis/Features/Plan/OnboardingPresenter.swift`
- Interview request/response models in `Models+Plan.swift` / `Endpoints+Plan.swift`

**docs** — `docs/deviations.md` gets a dated entry describing the redesign.

---

## Task 1: Schema — memories, improvement areas, check-ins, seeding kind

**Files:** modify `apps/api/src/db/schema.ts`; generate `apps/api/drizzle/0003_*.sql`

- [ ] **1.1** Add to schema.ts (after briefings section):

```ts
export const memorySource = pgEnum("memory_source", ["chat", "seeding", "manual"]);

// One durable fact per row. The AI's growing knowledge of the user —
// auto-extracted after chat turns, fully user-editable.
export const memories = pgTable("memories", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  category: text("category").notNull(), // identity|work|health|appearance|preferences|relationships|context
  content: text("content").notNull(),
  source: memorySource("source").notNull().default("chat"),
  conversationId: uuid("conversation_id").references(() => conversations.id, { onDelete: "set null" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [index("memories_user_idx").on(t.userId, t.category)]);

// Self-improvement areas (posture, clothing, teeth...) — weekly photo check-ins.
export const improvementAreas = pgTable("improvement_areas", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  emoji: varchar("emoji", { length: 16 }),
  // What "better" looks like — feeds the AI commentary prompt.
  betterLooksLike: text("better_looks_like"),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  archivedAt: timestamp("archived_at", { withTimezone: true }),
}, (t) => [uniqueIndex("improvement_areas_user_name_uq").on(t.userId, t.name)]);

// One check-in per area per ISO week (weekKey = that week's Monday dayKey).
export const areaCheckins = pgTable("area_checkins", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  areaId: uuid("area_id").notNull().references(() => improvementAreas.id, { onDelete: "cascade" }),
  weekKey: date("week_key").notNull(),
  dayKey: date("day_key").notNull(),
  blobKey: text("blob_key").notNull(),
  blobUrl: text("blob_url").notNull(),
  contentType: text("content_type").notNull(),
  sizeBytes: integer("size_bytes").notNull(),
  aiCommentary: text("ai_commentary"), // null until generated (async via after())
  aiModel: text("ai_model"),
  aiGeneratedAt: timestamp("ai_generated_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (t) => [uniqueIndex("area_checkins_week_uq").on(t.areaId, t.weekKey)]);
```

- [ ] **1.2** Change `conversationKind` enum to `["chat", "weekly_review", "block_review", "seeding"]`.
- [ ] **1.3** `pnpm --filter api db:generate` → verify SQL has 3 CREATE TABLE + 1 ALTER TYPE ... ADD VALUE + memory_source enum. (Do NOT drop `interview_sessions` — history preserved, code just stops using it.)
- [ ] **1.4** `pnpm --filter api typecheck` passes.

## Task 2: Memory subsystem (lib + tools + context + extraction hook + routes)

**Files:** create `src/lib/ai/memory.ts`, `src/app/api/v1/memories/route.ts`, `src/app/api/v1/memories/[id]/route.ts`, `tests/memory.test.ts`; modify `validation.ts`, `tiers.ts`, `context.ts`, `tools.ts`, `agent.ts`, `ai/chat/route.ts`

- [ ] **2.1** `validation.ts`: add

```ts
export const memoryCategories = ["identity","work","health","appearance","preferences","relationships","context"] as const;
export const memoryCreateSchema = z.object({
  category: z.enum(memoryCategories),
  content: z.string().min(1).max(500),
});
export const memoryPatchSchema = memoryCreateSchema.partial().strict();
```

- [ ] **2.2** `tiers.ts`: remove `interview_round`, `interview_synthesis`, `plan_generation`; add `memory_extraction: "fast"`, `checkin_commentary: "deep"`, `seeding: "fast"`.
- [ ] **2.3** `src/lib/ai/memory.ts`:
  - `memoryContextBlock(userId)` → loads all memories, groups by category, returns markdown block (or "" if none) for the system prompt.
  - `extractMemories(userId, conversationId, overrides)` → loads last 6 messages of the conversation + existing memories (id+category+content), calls `callModel` (task `memory_extraction`, strict JSON schema `{ ops: [{op:"add"|"update"|"delete", id: string|null, category, content: string|null}] }`), applies ops with `applyMemoryOps` (exported pure function: validates ids belong to user's loaded set, caps at 8 ops/turn, add→insert source "chat"/"seeding", update→content/category+updatedAt, delete→delete). Instructions: extract only durable facts about the user (role, situation, preferences, struggles, appearance goals) — never tasks, never one-off events, never things already stored verbatim; prefer update over duplicate add; empty ops when nothing new. Wrap whole function in try/catch that logs and swallows — extraction must never break a chat turn.
- [ ] **2.4** `context.ts`: after the profile section insert `## What you have learned about the user (long-term memory)` from `memoryContextBlock`; keep legacy profile section (prefixed "Onboarding profile (legacy)") only when it exists. Persona edits: replace the "Onboarding creates one" line with "The user starts one from the Plan tab — you never create plans for them."; add sentence: "The user authors their own goals and plans. You may refine or suggest when asked, and you remember durable facts about them (memory is automatic; use save_memory when they explicitly ask you to remember something)."
- [ ] **2.5** `tools.ts`: new MEMORY_TOOLS class executing inline (same trust level as automatic extraction):
  - `save_memory {category, content}` → insert (source "chat"), returns `{memoryId}`
  - `list_memories {}` → id/category/content list
  - Export `isMemoryTool`, `executeMemoryTool`; include in `openAIToolDefinitions()`.
- [ ] **2.6** `agent.ts`: in the function-call dispatch, handle `isMemoryTool` exactly like read tools (execute inline, push tool_call+tool_result parts, function_output).
- [ ] **2.7** `ai/chat/route.ts`: `import { after } from "next/server"`; after `runAgentTurn` resolves (inside stream start, after `message_done`), call `after(() => extractMemories(userId, conversationId, settings.aiOverrides))`.
- [ ] **2.8** Routes: `GET /memories` → `{ memories: [...] }` ordered category/createdAt; `POST /memories` (source "manual", 201); `PATCH /memories/[id]` ownership-checked; `DELETE /memories/[id]` → `{ok:true}`.
- [ ] **2.9** `tests/memory.test.ts`: unit-test `applyMemoryOps` decision logic (pure part: op filtering/validation given an existing set — add/update/delete/unknown-id/cap-at-8) and memory schemas. Run `pnpm --filter api test`.

## Task 3: Improvement areas + check-ins + AI commentary

**Files:** create `src/lib/checkins.ts`, `src/lib/ai/checkin-commentary.ts`, 3 route files, `tests/checkins.test.ts`; modify `validation.ts`, `provider.ts`, `tools.ts`

- [ ] **3.1** `validation.ts`:

```ts
export const improvementAreaCreateSchema = z.object({
  name: z.string().min(1).max(60),
  emoji: z.string().max(16).nullish(),
  betterLooksLike: z.string().max(2000).nullish(),
  sortOrder: z.number().int().optional(),
});
export const improvementAreaPatchSchema = improvementAreaCreateSchema.partial().extend({
  archived: z.boolean().optional(),
}).strict();
export const checkinUploadQuerySchema = z.object({ dayKey: dayKeySchema });
```

- [ ] **3.2** `src/lib/checkins.ts`: `weekKeyFor(dayKey)` (Monday of that ISO week — reuse `weekStart` from daykey.ts), `buildAreaDTO(area, thisWeekCheckin, latestCheckin)` → `{id,name,emoji,betterLooksLike,sortOrder,archived, dueThisWeek, thisWeek: {id,dayKey,hasCommentary}|null, lastCheckinAt}`. Pure; unit-testable.
- [ ] **3.3** `provider.ts`: widen `ModelCallOptions.input` to `string | Array<Record<string, unknown>>` (Responses API structured content for vision). No other changes.
- [ ] **3.4** `src/lib/ai/checkin-commentary.ts`: `generateCheckinCommentary(userId, checkinId, overrides)`:
  - Load check-in + area + up to 4 previous check-ins for the area (desc by weekKey).
  - Presign all photos (same `issueSignedToken`/`presignUrl` pattern as photos route).
  - `callModel` task `checkin_commentary`, input = `[{role:"user", content:[{type:"input_text", text: meta}, {type:"input_image", image_url: current}, ...previous images each preceded by an input_text label with its weekKey]}]`; instructions: J.A.R.V.I.S. persona (calm, dry, literal, no exclamation marks); compare THIS week's photo for area "<name>" (better looks like: <betterLooksLike>) against the labeled previous weeks; give 2–4 concrete observations and at most 2 specific suggestions; if first photo, baseline observations only; ~120 words max, no headings/emoji.
  - Persist `aiCommentary`, `aiModel`, `aiGeneratedAt`. try/catch: log + leave null (client shows "commentary pending"; regenerated on next GET if null — no, keep simple: only on upload; a failed generation can be retried by re-uploading. Acceptable: also regenerate lazily on GET timeline when null and older than 2 minutes? NO — YAGNI, skip; upload retriggers).
- [ ] **3.5** `improvement-areas/route.ts`: GET (areas incl. archived flag filter, join this-week + latest check-ins, return DTOs + `anyDueThisWeek`); POST create (409 on duplicate name).
- [ ] **3.6** `improvement-areas/[id]/route.ts`: PATCH (fields + archive/unarchive), DELETE (hard delete; best-effort blob `del()` of its check-in photos first).
- [ ] **3.7** `improvement-areas/[id]/checkins/route.ts`:
  - GET → timeline `{checkins: [{id, weekKey, dayKey, url (presigned), aiCommentary, aiGeneratedAt, createdAt}]}` desc.
  - POST (raw bytes, `?dayKey=`, same content-type/size guards as photos route, 4 MB): compute `weekKey = weekKeyFor(dayKey)`; if a check-in exists for (area, weekKey) → replace (delete old blob best-effort, update row, clear commentary); else insert. Then `after(() => generateCheckinCommentary(...))`. Return 201 DTO with presigned URL.
- [ ] **3.8** `tools.ts`: read tool `get_improvement_areas {}` → areas + due state + latest commentary snippet (lets chat discuss check-ins).
- [ ] **3.9** `tests/checkins.test.ts`: `weekKeyFor` across week boundaries (Sunday/Monday, year wrap), `buildAreaDTO` due logic (no checkin → due; this-week checkin → not due; archived → never due), schema validation. Run tests.

## Task 4: Onboarding v2 API — seeding kind + retire interview

**Files:** modify `ai/chat/route.ts`, `validation.ts`; delete interview lib/routes/tests

- [ ] **4.1** `validation.ts`: `chatRequestSchema` gains `kind: z.enum(["chat","seeding"]).optional()` (used only when creating a new conversation); delete `interviewStartSchema`.
- [ ] **4.2** `ai/chat/route.ts`: new conversation uses `kind: body.kind ?? "chat"`; map seeding→task "seeding"; when `conversation.kind === "seeding"` set extraInstructions = SEEDING_INSTRUCTIONS (constant in `context.ts` or inline): purpose = get to know the user (who they are, work situation incl. co-founder split, energy, what they want to improve incl. appearance areas, preferences for how to be spoken to); ask 1–2 concrete questions per turn, ≤8 questions total then wrap up with a summary of what you saved; call `save_memory` (source seeding is set server-side when conversation kind is seeding — implement: `executeMemoryTool` receives conversation kind via ToolContext extension) for every durable fact as you learn it; NEVER propose goals/habits/tasks/plans here.
- [ ] **4.3** Extend `ToolContext` with optional `conversationKind` so `save_memory` writes source "seeding" in seeding conversations; agent.ts passes it through.
- [ ] **4.4** Delete: `lib/ai/interview.ts`, `lib/ai/apply-plan.ts`, `app/api/v1/ai/interview/**`, `tests/integration/interview.*.test.ts`. Fix any dangling imports (`interviewStartSchema`, tiers). Conversation list responses already handle unknown kinds? Check `GET /ai/conversations` returns kind string — Swift `ConversationDTO` must decode "seeding" (Task 7 syncs).
- [ ] **4.5** `pnpm --filter api typecheck && pnpm --filter api test`.

## Task 5: Account reset

**Files:** create `src/app/api/v1/account/reset/route.ts`

- [ ] **5.1** POST body `{confirm: "RESET"}` (zod literal). Deletes in FK-safe order for `userId`: proposed_actions, messages, conversations, briefings, interview_sessions, memories, area_checkins (+ best-effort blob del), improvement_areas, tactic_completions (via tactics join), tactics, tasks, recurrence_templates, habit_completions, habits, goals, blocks, areas, vision, user_profile, mood_entries, daily_scores, metric_entries, metric_types, progress_photos (+ best-effort blob del). Keeps users/sessions/settings. Returns `{ok:true}`. (Most children cascade from parents, but delete explicitly — clarity over cleverness, and blobs need enumeration anyway.)
- [ ] **5.2** Manual verification deferred to Task 9 (end-to-end against dev DB with a scratch user).

## Task 6: JarvisAPI Swift package — new models/endpoints, remove interview

**Files:** create `Models+Memory.swift`, `Endpoints+Memory.swift`, `Models+Improve.swift`, `Endpoints+Improve.swift`, `MemoryImproveModelsTests.swift`; modify `Endpoints.swift`, `Endpoints+Chat.swift`, `Models+Chat.swift`, `Models+Plan.swift`, `Endpoints+Plan.swift`

- [ ] **6.1** Memory: `MemoryDTO {id, category, content, source, createdAt, updatedAt}`, `MemoryListResponse`; endpoints `memories()`, `createMemory(category:content:)`, `patchMemory(id:_:)`, `deleteMemory(id:)`.
- [ ] **6.2** Improve: `ImprovementAreaDTO {id,name,emoji,betterLooksLike,sortOrder,archived,dueThisWeek,thisWeek,lastCheckinAt}`, `ThisWeekCheckin {id,dayKey,hasCommentary}`, `AreaCheckinDTO {id,weekKey,dayKey,url,aiCommentary,aiGeneratedAt,createdAt}`, list responses incl. `anyDueThisWeek`; endpoints `improvementAreas()`, `createImprovementArea(...)`, `patchImprovementArea(id:_:)`, `deleteImprovementArea(id:)`, `checkins(areaId:)`, `uploadCheckin(areaId:dayKey:data:contentType:)` (uses existing `upload()`).
- [ ] **6.3** Chat: `sendMessage`/stream entry gains optional `kind: String?` in the POST body for new conversations; `ConversationDTO.kind` tolerant of "seeding".
- [ ] **6.4** Reset: `resetAccount()` → POST `/account/reset` body `{"confirm":"RESET"}`.
- [ ] **6.5** Remove interview endpoints/models (`Models+Plan.swift`, `Endpoints+Plan.swift`) — everything referencing `/ai/interview`.
- [ ] **6.6** Decoding tests for the new DTOs with representative JSON; `swift test` in `Packages/JarvisAPI`.

## Task 7: Swift — Setup Wizard replacing AI onboarding

**Files:** create `Features/Setup/*` (3 files); modify `RootView.swift`, `AppModel.swift`, `Features/Plan/PlanView.swift`+`PlanStore.swift`; delete `Features/Onboarding/*`, `Features/Plan/OnboardingPresenter.swift`

- [ ] **7.1** `SetupWizardStore` (@Observable): step enum (welcome, areas, block, goals, habits, improve, seed, done), local draft arrays, `apply()` calls: POST /areas per area → POST /blocks {title,startDate: next Monday} → activate if API doesn't auto-activate (check blocks route semantics during impl) → POST /goals (blockId, areaId) → POST /habits → POST /improvement-areas. Errors surface inline, retryable per step.
- [ ] **7.2** `SetupWizardView`: paged flow, DesignSystem styling, progress dots; every list step allows add/edit/remove/skip; Block step = title + start date (defaults next Monday, snapped Monday); Goals capped 6 w/ hint "2–4 goals you will actually do — this is YOUR plan, J.A.R.V.I.S. never writes it"; Habits step mirrors HabitEditor basics (name, type, target); Improve step explains weekly photo check-ins; Seed step embeds a seeding chat ("Optional: let J.A.R.V.I.S. get to know you — it plans nothing, it only remembers") with skip; Done step.
- [ ] **7.3** Presentation: `setupWizardCover(isPresented:)` modifier (fullScreenCover iOS / sheet macOS) replacing `onboardingInterviewCover`; RootView first-run hook now presents wizard. PlanView empty state ("no block") button → wizard; remove reonboarding/interview launch points.
- [ ] **7.4** Delete `Features/Onboarding/` + `OnboardingPresenter.swift`; fix references.

## Task 8: Swift — Improve UI + Today card + Memory screen

**Files:** create `Features/Improve/*` (5 files), `Features/Today/CheckinPromptCard.swift`, `Features/Settings/MemoryView.swift`; modify `RootView.swift`, `TodayView.swift`, `TodayStore.swift`, `SettingsView.swift`, `ConversationListView.swift`

- [ ] **8.1** `AppSection.improve` ("Improve", icon "sparkles"): macOS sidebar Progress group (trends, body, improve); iPhone reachable from Today toolbar (like Trends/Body).
- [ ] **8.2** `ImproveStore`: load areas+checkins, upload (reuse `ImageDownscaler`), create/edit/archive areas.
- [ ] **8.3** `ImproveView`: rows (emoji, name, "due this week" badge, last-checkin relative date, latest thumbnail); toolbar +; empty state explains the concept.
- [ ] **8.4** `ImprovementAreaDetailView`: newest-first timeline — week label, photo (tappable full-screen), commentary text or "J.A.R.V.I.S. is looking at this…" pending state with pull-to-refresh; "Check in now" when due; edit/archive menu.
- [ ] **8.5** `CheckinFlowView`: given due areas, one page per area — PhotosPicker (+ camera on iOS), preview, upload (downscaled JPEG ≤4 MB), next; end screen "J.A.R.V.I.S. will comment shortly — see Improve."
- [ ] **8.6** `CheckinPromptCard` on Today (below mood card): visible when `anyDueThisWeek`; "Weekly check-in — N areas due"; button opens CheckinFlowView. TodayStore fetches improvement areas alongside today payload (parallel, failure-tolerant).
- [ ] **8.7** `MemoryView`: sections per category; rows editable (sheet with category picker + text); swipe/context delete; toolbar add; footer "J.A.R.V.I.S. updates this automatically after conversations." Entries: SettingsView row "What J.A.R.V.I.S. knows" + ConversationListView toolbar brain icon.
- [ ] **8.8** SettingsView Danger zone: "Reset all data…" → confirmation dialog (destructive, explains scope) → `resetAccount()` → on success set `needsFirstRunOnboarding = true`, bump `todayRevision`, present wizard.

## Task 9: Verify + migrate + docs

- [ ] **9.1** `pnpm --filter api typecheck && pnpm --filter api test` — all green.
- [ ] **9.2** `swift test` (JarvisAPI), then `xcodebuild -project apps/app/Jarvis.xcodeproj -scheme Jarvis -destination 'platform=macOS' build` and iOS Simulator build — zero errors.
- [ ] **9.3** Apply migration to Neon: `pnpm --filter api db:migrate` with env via enkryptify skill.
- [ ] **9.4** Run dev API + exercise endpoints end-to-end with curl + scratch user: register → wizard-equivalent calls → memories CRUD → improvement area + photo check-in upload (tiny test JPEG) → verify commentary generated → chat turn → verify extraction wrote memories → account reset → verify tables empty for that user.
- [ ] **9.5** `docs/deviations.md`: dated entry — interview/plan-generation removed, memories/improvement-areas/seeding/reset added, spec §references updated.
- [ ] **9.6** Final report to user incl. the one manual step: tapping "Reset all data" in Settings on their own logged-in device (or confirming I run it against their account row).

## Self-review notes
- Spec coverage: reset (T5), user-authored (T4 removal + T7 wizard), onboarding v2 both halves (T7 wizard + T4 seeding), improvement areas weekly photo check-ins + AI commentary + Today card no-push (T3 + T8), growing memory + editable screen (T2 + T8). Unchanged: scoring/mood/trends untouched.
- Type consistency: DTO names in T6 match route payloads in T2/T3; `weekKeyFor` single source in checkins.ts used by both route and tests.
- Placeholders: Swift step specs are behavioral but name exact files, stores, endpoints, and states; API code is given at near-final fidelity. Executor is the plan author (same session).
