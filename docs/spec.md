# J.A.R.V.I.S. — Personal Life Assistant (Full Build Plan)

## Context

Siebe wants a personal J.A.R.V.I.S.-style assistant app that helps him achieve long-horizon life goals (business discipline, appearance — muscle/posture/teeth/face/hair/clothes, social skills) by breaking them down 12-Week-Year-style into quarterly blocks, daily tasks, and habits, with an AI companion that deeply knows him from an onboarding interview and keeps him motivated day-by-day via a daily score, streaks, briefings, and coaching conversations.

The repo is empty (previous Expo experiment deleted; total reset — prior memory intentionally ignored). Everything is built from scratch: a monorepo with `apps/api` (Next.js on Vercel, NeonDB Postgres, Drizzle) and `apps/app` (SwiftUI, iPhone iOS 26 + macOS 26). **Nothing is hardcoded** — all areas, goals, habits, and metrics come from onboarding + user configuration.

## Locked-in decisions (from user interview)

| Topic | Decision |
|---|---|
| Planning model | Vision (dream life, no deadline) → 12+1-week blocks aligned to quarters (12 Week Year). Week 13 = review + reset (tasks pause, habits continue, AI retrospective + re-onboarding) |
| AI role | Full daily companion: onboarding interview, plan generation, chat agent with tool use + confirmable action cards, morning briefing, weekly review, week-13 retrospective |
| AI model | OpenAI GPT-5.6 Luna. Try Codex-subscription auth first, fall back to API-key billing. High reasoning for deep tasks (interview, plan gen, reviews); low/minimal for chat + briefings. All model config env-driven |
| Daily score | /100 = 40% tasks due today + 40% habits + 20% feel. Weights stored in DB, tunable |
| Mood ("feel") | Anytime slider on Today page, editable all day, backfillable next morning; if absent, score renormalizes over the other 80 pts. (Reminder will become a push notification later; in-app indicator for now) |
| Habits | User-defined. Daily, N×/day (proportional credit: 1 of 2 = 50%), N×/week (pace-based daily credit; planned days are soft defaults — swapping days never penalized, only weekly total counts) |
| Habit views | Per-habit detail: stats + monthly calendar distinguishing full vs partial completion. Streaks (weekly habits streak in weeks). Score trend charts 7/30/90d, weekly avg vs previous week |
| Tasks | Due date + optional time, priorities, subtasks/checklists (% feeds parent), recurring tasks, optional goal link (free-standing allowed), overdue rolls into today flagged |
| Body tracking | Progress photos (Vercel Blob, timeline view) + self-tracked numeric metrics (weight, body fat %, user-defined types) with trend charts. No tape measurements |
| Day/week | Day boundary 3:00 AM local; week starts Monday |
| Notifications | **None for now** (free Apple account; user declined local notifications). All reminder/briefing concepts are in-app surfaces. Push = future stage when paid account exists |
| Platforms | SwiftUI multiplatform: iPhone (iOS 26) + macOS 26. No iPad |
| Styling | Attio-inspired: clean, hairline borders, restrained accent, great typography. Light + dark, follow system |
| Offline | Online-only (no offline mode, no sync queue) |
| Auth | Email/password, single user, no email verification |
| Stack | pnpm monorepo; `apps/api` Next.js (Vercel) + Drizzle + Zod + NeonDB; `apps/app` SwiftUI; photos on Vercel Blob |
| Staging | Stage 1 core tracking → Stage 2 AI onboarding + plan → Stage 3 chat + briefings → Stage 4 reviews, week-13, body metrics, polish |

---

# Part A — Technical architecture

## A1. Monorepo layout

pnpm workspace + Turborepo. No `packages/` split on the JS side (Swift can't consume TS; API-internal modules live in `apps/api/src/lib`).

```
jarvis/
├── package.json / pnpm-workspace.yaml / turbo.json / .env.example
├── apps/
│   ├── api/                      # Next.js App Router, route handlers only (no UI)
│   │   ├── drizzle.config.ts + drizzle/   # generated SQL migrations, checked in
│   │   ├── src/db/{schema.ts, client.ts}  # Drizzle + Neon HTTP driver
│   │   ├── src/lib/
│   │   │   ├── auth.ts, daykey.ts, recurrence.ts
│   │   │   ├── scoring/{engine.ts, snapshot.ts}   # pure, unit-tested
│   │   │   ├── ai/{provider.ts, tiers.ts, tools.ts, agent.ts, interview.ts, briefing.ts, context.ts}
│   │   │   └── validation/       # Zod schemas per domain
│   │   ├── src/app/api/v1/...    # route handlers
│   │   └── tests/                # vitest: scoring, daykey, recurrence
│   └── app/                      # SwiftUI multiplatform (iPhone iOS 26 + macOS 26)
│       ├── project.yml           # XcodeGen (xcodeproj gitignored — agent-friendly)
│       ├── Packages/{JarvisAPI, DesignSystem}   # local SPM packages
│       └── Jarvis/               # app target: AppModel + Features/
└── docs/spec.md
```

**Xcode project via XcodeGen**: `.pbxproj` is merge-hostile for agents; `project.yml` is ~40 declarative lines, adding a file = dropping it in a folder. `brew install xcodegen && xcodegen generate`.

## A2. Database schema (Drizzle / Postgres on Neon)

Conventions: `uuid` PKs, `timestamptz` instants, `date` columns store **dayKeys** (calendar date after 3 AM-boundary adjustment in user TZ). Everything keyed by `userId` (future-proof) with singletons (`settings`, `vision`, `user_profile`) using `userId` as PK. Archive instead of delete where history matters.

Tables (full column detail to be written exactly as specced during build):

- **users** (email unique, `password_hash` argon2id), **sessions** (`token_hash` = sha256 of raw 256-bit bearer token, deviceName, lastUsedAt, revokedAt; long-lived, no expiry)
- **settings** (singleton): timezone (default Europe/Brussels), dayBoundaryHour=3, weekStartsOn=1 (Mon), `score_weights` jsonb `{tasks:40,habits:40,feel:20}`, moodScaleMax=5 (stored 0–100 canonical), `ai_overrides` jsonb (baseUrl/authMode/models/efforts — DB overrides env)
- **vision** (singleton): dream-life long-form text
- **blocks**: number (lifetime counter), title, startDate (a Monday), endDate (= start + 13×7 − 1 → 12 weeks + review week 13), status planned/active/completed. Invariants (app-enforced): no overlap, ≤1 active. Week N = `floor((dayKey−start)/7)+1`; week 13 = review week
- **goals**: blockId FK, title, description, status active/achieved/dropped, sortOrder
- **tasks**: title, notes, dueDate (dayKey, null = inbox/someday), dueTime, priority low/med/high, status open/done/cancelled, completedAt, goalId?, parentTaskId? (subtasks), templateId + templateDate (recurrence occurrence dedupe, unique index), sortOrder
- **recurrence_templates**: title/notes/priority/goalId/dueTime + `rule` jsonb (`daily every-N` | `weekly interval + byWeekday[]` | `monthly interval + byMonthDay` — deliberately simpler than RRULE), startDate/endDate, pausedAt, `last_generated_through` high-water mark
- **habits**: name, emoji, colorHex, type `daily | multi_daily | weekly_frequency`, targetReps (1 / N per day / N per week), `planned_days` jsonb (ISO weekdays — **cosmetic soft defaults, never used in scoring**), goalId?, startDate, archivedAt, sortOrder
- **habit_completions**: one row **per rep** (habitId, dayKey, completedAt) — reps = COUNT(*); undo = delete latest row
- **mood_entries**: PK (userId, dayKey), value 0–100, note — natural upsert, backfill = write past dayKey
- **daily_scores** (materialized snapshot): PK (userId, dayKey), total, taskPoints/habitPoints/feelPoints (null = not applicable), applicableWeight (denominator used), isReviewWeek, `breakdown` jsonb (per-task credit + late flag; per-habit credit/reps/expected/reconciled flag), **isFinal**, computedAt
- **metric_types** (user-defined: name+unit, e.g. Weight/kg, Body fat/%), **metric_entries** (unique per type+dayKey, upsert), **progress_photos** (Vercel Blob key, angle front/side/back/other, dayKey, contentType, size)
- **user_profile** (singleton jsonb: values, constraints, schedule, motivations, context — what Jarvis knows about you)
- **interview_sessions**: status active/completed/applied/abandoned, transcript jsonb, providerResponseId (OpenAI Responses chaining), result jsonb (profile + visionDraft + plan)
- **conversations** (kind chat/weekly_review/block_review, title, blockId?, weekNumber?, outcome jsonb), **messages** (role user/assistant/tool, `parts` jsonb: text | tool_call | tool_result)
- **proposed_actions**: conversationId, messageId, toolName, args (zod-validated), summary (template-generated, not model-generated), status proposed/executed/rejected/expired, result
- **briefings**: PK (userId, dayKey), content markdown, model

APNs-later readiness: adding push later only needs a new `devices` table — nothing above changes.

## A3. REST API (`/api/v1`, bearer auth, Zod-validated, errors `{error:{code,message}}`)

- **Auth [S1]**: `POST /auth/login` (`{email,password,deviceName}` → `{token,user}`), `POST /auth/logout`, `GET /auth/me`, `POST /auth/register` (rejects if a user already exists — single-user bootstrap)
- **Settings [S1]**: `GET/PATCH /settings` (weights must sum to 100)
- **Days/scores [S1]**: `GET /days/today` — the one-shot Today payload `{dayKey, weekNumber, isReviewWeek, block?, score{total,components,breakdown}, tasksDue[], overdueTasks[], habits[{habit,repsToday,weekProgress,credit}], mood?}`; triggers recurrence materialization + provisional score compute. `GET /days/:dayKey` (historical), `GET /scores?from&to` (trends), `GET /scores/weekly?blockId` [S4]
- **Tasks [S1]**: CRUD + `POST /tasks/:id/complete|uncomplete` (recomputes the task's due-date score), `?view=today|upcoming|inbox`; `GET/POST/PATCH/DELETE /recurrence-templates` (edits affect future occurrences only)
- **Habits [S1]**: CRUD + archive; `POST /habits/:id/log {dayKey?}` (add one rep) / `DELETE /habits/:id/log` (remove latest rep); `GET /habits/:id/calendar?month=` → `[{dayKey,reps,target,credit,state: full|partial|none|not_applicable}]`; `GET /habits/:id/stats` (streaks, 7/30/90 rates, weekly totals)
- **Mood [S1]**: `PUT /mood/:dayKey` (upsert; any past day allowed, future rejected; recomputes that day), `GET /mood?from&to`
- **Vision/Blocks/Goals [S2]**: `GET/PUT /vision`; blocks CRUD + `POST /blocks/:id/activate` (validates Monday-aligned 13-week, no overlap) + `GET /blocks/current`; goals CRUD
- **Metrics/photos [S4]**: metric-types CRUD; `PUT /metrics/:typeId/:dayKey`; `POST /photos/upload-url` (Vercel Blob client-upload token) → `POST /photos/:id/confirm`; `GET /photos` (60-min signed URLs); `DELETE /photos/:id`
- **AI**: `POST /ai/interview/start|:id/answer|:id/apply` [S2]; `POST /ai/chat` (SSE) + conversations list/detail + `POST /ai/actions/:id/confirm|reject` + `GET /ai/briefing/today` [S3]; `POST /ai/reviews/weekly/start` + `POST /ai/reviews/:conversationId/close` [S4]

## A4. Scoring algorithm (exact spec)

**Day/week math** (`daykey.ts`, mirrored in Swift for display only — server is source of truth for all persisted dayKeys):
```
dayKey(instant) = calendarDate(toLocal(instant, tz) − 3h)     # 02:30 → yesterday; 03:00 → today
weekStart = ISO Monday; weekIndexInBlock = floor((dayKey − block.start)/7)+1; review week = 13
elapsedDayOfWeek = Mon=1..Sun=7
```

**Task credit**: parent with subtasks → done/total fraction; else done ? 1 : 0. Task component = mean credit over tasks **due that dayKey** (top-level, non-cancelled); no tasks due → component NOT_APPLICABLE (drops out of denominator — a rest day is neither free points nor penalty). **Overdue**: counts only against its original due date; completing late **retro-credits** that historical day (recomputed, flagged `late`) — overdue tasks appear in Today flagged but don't enter today's formula (no double counting; rewards closing loops).

**Habit credit**:
```
daily:        min(1, reps/1)
multi_daily:  min(1, reps/targetReps)            # 1 of 2 = 0.5
weekly_frequency:
  live (current week):  expected = targetReps × elapsedDayOfWeek/7
                        credit = min(1, doneThroughDay / expected)     # pace-based
  reconciled (week over): credit = min(1, weekReps/targetReps) applied UNIFORMLY to all 7 days
```
Two phases because pure pace would permanently punish back-loading (skip Mon, do 5 sessions Tue–Sat must score perfectly). Live = motivational feedback; at week end every day reconciles to the weekly-total credit and only then finalizes. `plannedDays` never enters scoring. Habit component = mean over active habits (equal weights v1).

**Feel**: mood value/100; missing → NOT_APPLICABLE.

**Total** (renormalization): sum applicable `weight × raw` ÷ sum applicable weights × 100. Week 13 drops the tasks component entirely. All components missing → total null (render "—", not 0).

**Snapshotting** (`daily_scores`): recompute synchronously on every relevant mutation (task complete, habit log, mood upsert, habit create/archive, weight change → today only; history keeps the weights it was scored with — `applicableWeight` + breakdown make rows self-describing). **Lazy finalization, no cron**: on any authenticated request, finalize past days whose *week* has fully ended (weekly reconciliation needs the complete week); current-week days stay provisional. Backfill edits recompute single days, stay `isFinal`, flag `late`/`reconciled`.

**Streaks**: daily habits = consecutive days at credit 1.0 (full completion; partial breaks it — streak is the "hard" metric, score is the forgiving one; incomplete *today* doesn't break until boundary passes). Weekly habits = consecutive completed weeks hitting target; in-progress week ignored unless already hit.

## A5. AI layer

**Provider** (`provider.ts`): official `openai` npm package against the **Responses API** (native `previous_response_id` chaining, `json_schema` structured outputs, reasoning-effort control). Everything env-driven, `settings.ai_overrides` layered on top. Tier map in `tiers.ts` (config, not code-scattered): `interview_round/interview_synthesis/plan_generation/weekly_review/block_review → deep (high effort)`, `chat/briefing/conversation_title → fast (low/minimal effort)`.

**Codex-subscription experiment** (`AI_AUTH_MODE=codex_oauth`): run `codex login` locally, copy access+refresh tokens into env; provider injects bearer, refreshes on 401, persists new tokens in `settings.ai_overrides`. Flagged risks: undocumented endpoint, possible model restrictions, likely ToS-gray. **Mandatory automatic fallback** to `api_key` mode (`OPENAI_API_KEY`) after two auth failures, surfaced as `aiAuthMode:"fallback"` in settings. Build `api_key` first; wire the experiment after.

**Interview protocol**: state in `interview_sessions`; every model turn returns strict JSON — either `{done:false, questions:[{id, question, type: single_choice|multi_choice|free_text|scale, options?, allowFreeText:true (always), rationale?}]}` (1–3 questions/round, unlimited rounds, soft server cap 25 as runaway guard) or `{done:true, result:{profile, visionDraft, plan:{block, goals[], habits[], tasks[]}}}`. Client renders questions **natively** (not a chat). `apply` takes the **user-edited** payload and creates everything in one transaction. Nothing is created before apply.

**Chat agent** (`agent.ts`): server-side loop, max 8 iterations. Read tools execute inline (`get_today_summary`, `get_day`, `get_score_trends`, `list_tasks/habits/goals`, `get_habit_stats`, `get_mood`, `get_metrics`). **Mutating tools never execute from the loop**: model's tool call is zod-validated → `proposed_actions` row (summary generated from args by template, not by the model) → synthetic tool result `{"status":"pending_user_confirmation"}` fed back so the model can reference the card and stack several proposals per turn. `confirm` executes the *stored args* through the same service layer as REST (deterministic, model not re-invoked) and appends a real `tool` message; `reject` likewise; 24 h auto-expire. Mutating tools: create/update/complete/delete_task, create/update/archive_habit, create/update_goal, log_habit, set_mood, update_vision.

**Context injection** per request: persona + settings + user_profile + vision (truncated) + current block/week/goals + today snapshot + confirmation-protocol instruction. History: last 30 messages verbatim.

**Streaming**: SSE over POST route handlers (Node runtime, `maxDuration=120`): events `message_delta`, `tool_call`, `action`, `message_done`, `error`. Swift consumes via `URLSession.bytes(for:)` — no dependency.

**Briefing**: `GET /ai/briefing/today` — cached per dayKey, generated lazily on first open (fast tier; input = today snapshot + yesterday's final score + overdue + week pace), `pg_advisory_xact_lock` against double-generation. Vercel Cron can pre-warm later with zero schema change. **Reviews**: `weekly_review`/`block_review` conversations seeded with computed week/block stats, run on deep tier through the same agent loop (so reviews can apply adjustments via action cards); `close` produces structured outcome `{wins, struggles, adjustments, focusNextWeek}`.

## A6. SwiftUI app architecture

One multiplatform target `Jarvis` (iPhone iOS 26 + native macOS 26, no Catalyst, no iPad) + `JarvisTests`, managed by XcodeGen. Two local SPM packages:
- **JarvisAPI**: `APIClient` actor (URLSession, bearer injection, 401 → logout), one endpoint file per domain, hand-written Codable DTOs, `SSE/EventSource.swift` (~60-line line parser)
- **DesignSystem**: tokens (colors/typography/spacing), ScoreRing, HabitPill, ActionCardView, calendar heat-grid

App target: `JarvisApp` (@main) → `AppModel` (@Observable root: session, settings, todaySnapshot, `todayRevision` counter for cross-feature invalidation), `Support/` (Keychain wrapper — kSecClassGenericPassword, AfterFirstUnlock; DayKey mirror; Config with Debug→localhost:3000 / Release→prod via xcconfig), `Features/` — one folder per feature, each an @Observable store exposing `LoadState<T>` + views: Auth, Today, Tasks, Habits, Mood [S1]; Onboarding, Plan (Vision/Block/Goals) [S2]; Chat, Briefing [S3]; Reviews, Body, Trends-polish [S4]; Settings.

**Zero third-party dependencies**: URLSession, Swift Charts (score/metric trends; the habit calendar is a custom LazyVGrid heat-grid), Keychain Services, PhotosPicker. Online-only: no persistence beyond token + UI prefs; fetch on appear + `.refreshable`.

**Navigation**: iOS `TabView` (Today, Plan, Chat, Body, Settings) with per-tab NavigationStack + Hashable route enums; macOS `NavigationSplitView` sidebar with the same sections, chat as two-pane. Platform conditionals only at the navigation shell.

## A7. Environment & local dev

```
DATABASE_URL=postgres://...neon.tech/jarvis?sslmode=require    # Neon pooled
AUTH_PEPPER=<random>            BLOB_READ_WRITE_TOKEN=<vercel blob>
AI_BASE_URL=https://api.openai.com/v1     AI_AUTH_MODE=api_key|codex_oauth
OPENAI_API_KEY=sk-...           AI_MODEL_DEEP=gpt-5.6-luna   AI_MODEL_FAST=gpt-5.6-luna-mini
AI_EFFORT_DEEP=high             AI_EFFORT_FAST=low
AI_CODEX_ACCESS_TOKEN= / AI_CODEX_REFRESH_TOKEN=   # experiment only
```
(Model IDs are env values — verify exact published IDs at build time; nothing hardcoded.)

- DB: **Neon branches** — `main` = prod, `dev` branch for local (same HTTP driver as prod, instant reset). Migrations: `drizzle-kit generate` → checked-in SQL → `drizzle-kit migrate` (Vercel build runs migrate before `next build`).
- API: `pnpm --filter api dev` via `enkryptify run` (repo already has `.enkryptify.json`).
- App: `xcodegen generate && open Jarvis.xcodeproj`; Debug xcconfig exposes `API_BASE_URL` (localhost for sim/Mac; LAN IP for physical iPhone).
- Tests: vitest on scoring engine, daykey math (incl. DST dates), pace/reconciliation, recurrence — written in Stage 1.

### A8. Reconciliation additions (from UX design pass)

The UX spec introduced three concepts the schema must also carry:

1. **Areas** (life areas: e.g. Business / Appearance / Social — user-defined, from onboarding, nothing hardcoded): `areas` table (id, userId, name, emoji, colorHex, sortOrder, archivedAt) + nullable `areaId` FK on `goals` and `habits`. Ships in Stage 1 schema (habit grouping uses it); managed via a minimal editor; populated properly by onboarding in Stage 2.
2. **Weekly tactics** (12 Week Year's execution layer, distinct from tasks): `tactics` (id, userId, goalId, title, fromWeek, toWeek, sortOrder) + `tactic_completions` (tacticId, weekNumber, completedAt, unique per tactic+week). Tactics do **not** enter the daily score; they feed goal progress % (computed = completed tactic-weeks / applicable tactic-weeks, with optional `goals.manualProgress` override column). Interview plan output includes tactics per goal. Ships in Stage 2.
3. **Goal status pill**: `goals.trackStatus` enum (on_track / at_risk / done) set during weekly reviews.

**Pace: scoring vs display.** Scoring uses the continuous formula (§A4). The UI status chip uses a friendlier display rule: on-pace iff `done ≥ ceil(target × elapsed_full_days / 7)`, and before 18:00 today doesn't count as elapsed (so the app never calls you "behind" at 7 AM). Both live in `daykey.ts`/engine + mirrored display logic in Swift.

**Canonical decisions where the two specs differed**: monorepo path is `apps/app` (not `apps/apple`); DesignSystem/JarvisAPI are local SPM packages per §A6; iPhone tab bar is the UX spec's version (Today, Tasks, Habits, Plan, Chat — Settings via gear on Today, Trends/Body via toolbar links, tab bar grows by stage without reshuffling).

---

# Part B — Product / UX specification

## B0. Product principles (govern every screen)

1. **Today is the center of gravity** — the app always opens there.
2. **Nothing hardcoded** — areas, goals, habits, metrics, interview content are all data; every list has a real empty state.
3. **Calm, not gamified** — Attio restraint: no confetti, no badges. The one reward moment: a brief score-ring fill animation.
4. **AI acts only with consent** — every AI mutation is a confirmable card. The AI can dismiss its own pending cards but never confirm them.
5. **Never punish flexibility** — weekly habits judge the week, not the day. Swapping a gym day is zero-guilt (no red, ever, for planned-day misses).
6. **In-app only** — no notifications exist; briefing / mood reminder / evening wrap-up are contextual in-app surfaces.
7. **Day = 3 AM→3 AM; week = Mon→Sun.** At 1:30 AM the app shows "Late night — still counts for Wednesday."

## B1. Navigation

**iPhone — TabView** (grows by stage, never reshuffles): Today `sun.max` [S1] · Tasks `checklist` [S1] · Habits `repeat` [S1] · Plan `map` [S2] · Chat [S3]. Settings = gear in Today nav bar (sheet). Trends [S4] = chart icon in Today nav bar. Body [S4] = entry inside Trends/Progress. Each tab owns a NavigationStack; editors = sheets; flows (onboarding, reviews) = full-screen covers.

**macOS — NavigationSplitView**: sidebar sections — Today ⌘1, Chat ⌘2 [S3]; PLAN: Vision, Current Block · Week N ⌘3, Goals [S2]; TRACK: Tasks ⌘4, Habits ⌘5 [S1]; PROGRESS: Trends, Body [S4]; Settings pinned bottom (⌘,). "Current Block · Week 7" label is live; week 13 shows "Review Week" + accent dot. **Chat is dual-mode on Mac**: sidebar destination AND a global 360 pt slide-over panel (⇧⌘J) available from every screen. Detail column min 640 pt; content column max 760 pt centered except Tasks/Habits tables; Tasks/Habits use inspector-style right panels (320 pt) instead of pushing.

**Screen inventory** (24 screens): Login [S1]; Today [S1]; Score Breakdown sheet [S1]; Tasks List / Task Detail+Editor [S1]; Habits List / Habit Detail / Habit Editor [S1]; Settings [S1]; Onboarding Interview / Plan Proposal Review / Vision / Block Overview / Goal Detail / Week Detail [S2]; Chat / Morning Briefing [S3]; Weekly Review / Week-13 Retrospective / Trends / Body-Metrics / Body-Photos / Photo Compare / Add-entry sheets [S4].

## B2. Design tokens (Attio-inspired; implement once in DesignSystem)

**Color** (light / dark): `bg.canvas` #FAFAF9/#111113 · `bg.surface` #FFFFFF/#1A1A1D · `bg.subtle` #F4F4F3/#232326 · `bg.hover` #F0F0EF/#28282C · `border.hairline` #E7E7E5/#2E2E33 · `border.strong` #D4D4D2/#3D3D44 · `text.primary` #18181B/#F2F2F0 · `text.secondary` #6E6E76/#9E9EA7 · `text.tertiary` #A3A3AB/#6B6B74 · `accent` (restrained indigo) #4F46E5/#7C74F5 + `accent.subtle` #EEEDFC/#2A2843 · `success` #16A34A/#4ADE80 + subtle · `warning` #D97706/#FBBF24 · `danger` #DC2626/#F87171 · mood gradient red→amber→green. Rules: accent used sparingly (CTAs, selection, links, tasks arc); success green = "done" everywhere; never large accent fills.

**Type** (SF Pro): displayScore 44 semibold rounded mono-digits · title1 26 semibold · title2 20 semibold · headline 15 semibold · body 15/22 · subhead 13 · caption 12 medium uppercase +0.6 tracking · mono 13 SF Mono. All stats use monospaced digits.

**Layout**: spacing 4/8/12/16/20/24/32; margins 16 iPhone / 24 Mac; radii — cards/rows 10, sheets 16, buttons/inputs 8, chips 6; cards = surface + 1 px hairline, **no shadow** (only popovers/pending action cards: y2 blur12 8%); rows 44 pt iPhone / 36 pt Mac; primary button = accent fill 36 pt/r8. Animations 0.25 s ease-out; ring 0.6 s spring; respect Reduce Motion.

## B3. Pages (layout, interactions, empty states)

**Login [S1]**: wordmark → email → password → Sign in + inline error slot. Create-account toggle on the same form (register rejects once a user exists). Offline → reusable full-screen "You're offline" retry panel (global pattern). Mac: centered 360 pt.

**Today [S1, grows S2–S4]** — top to bottom:
1. Nav: gear (Settings) · "Today" · chart icon (Trends S4). Date line + week chip `Week 7 · Block 2` [S2, taps to Block]. 00:00–03:00 caption: "Late night — still counts for Wednesday."
2. **Briefing card [S3]** — expanded on first open of the day, collapsed after, dismiss = collapse only. Expanded: 2–3 AI sentences → compact facts (tasks count, habit targets + week pace, week avg vs last) → one dry motivational line (calm JARVIS, no exclamation marks) → "Open chat about today". Shimmer while generating; static data-only fallback + retry on failure.
3. **Score header**: 120 pt segmented ring (§B5.1) + three component micro-rows ("Tasks 28/40" etc. with 4 pt bars). Tap → Score Breakdown.
4. **Mood card**: "How do you feel today?" + 0–100 gradient slider. Unset = hollow knob, "—", faint accent tint (the in-app mood reminder). Editable all day. **Backfill row** appears beneath until 12:00 if yesterday unset: "Yesterday's feel? ◦——◦ Skip" — set recomputes yesterday; Skip renormalizes and dismisses.
5. **OVERDUE** (conditional, warning caption): rows flagged "was due Tue"; swipe right complete, swipe left reschedule (Today/Tomorrow/Pick).
6. **TASKS**: sorted priority→time. Row: checkbox · title · meta line (time, goal chip, subtask "2/5") · priority flag (P1 danger/P2 warning/P3 gray). Complete → fill animation, moves to collapsed "Completed (n)" group. Subtask progress = thin underline. "+ Add task" ghost row = inline quick-add (title + date/time/priority chips, "More…" → full editor).
7. **HABITS**: one row per habit active today (controls per type, §B5.2). Tap = log; long-press → Undo last / Skip today / View details. Weekly habits not planned today sit in a subdued "Also available" subgroup — loggable, promoting on tap (the day-swap mechanic).
8. **Evening wrap-up banner [S3]**: from 20:00 or all-done: near-final score + one AI sentence + "Set my feel" / "Done for today" (collapses).
Empty states: no tasks → "Nothing scheduled today" + Add; no habits → deep link to Habits tab; brand-new S1 user → hero "Start by adding your first task or habit."

**Score Breakdown [S1]** (sheet/popover): 160 pt ring; three cards — Tasks "5 of 7 · 28.6/40" with per-task ✓/✗; Habits "80% · 32/40" with per-habit credit rows ("Brush teeth 1/2 → 50%"); Feel "72 → 14.4/20" or "Not set — renormalized over 80 pts" with the exact math line. Footer: weights caption. Historical days open read-only with date title.

**Tasks List [S1]**: segments Today · Upcoming · All · Done. Upcoming grouped by day ("Tomorrow", "Friday Jul 12", "Later", "No date"). Recurring glyph after title; overdue pinned red-captioned. Swipe complete/reschedule; search; Mac = sortable table (Title/Due/Priority/Goal), drag-between-day-groups reschedules, ⌘N new.

**Task Detail/Editor [S1]**: inline-editable title → status row → properties (Due, Time, Priority, Repeat: none/daily/weekly-on-days/monthly-day-n/every-N with editor sheet, Goal picker "None" allowed) → Subtasks checklist (add, drag-reorder; fractions feed parent + daily score) → Notes → Delete (recurring asks This occurrence / All future). Completing an occurrence reveals the next per rule ("Next: Aug 1").

**Habits List [S1]**: header week-pace summary ("This week · 4 of 6 habits on pace" + dot row). Habit cards grouped by area: icon+name · type caption ("Weekly · 5×/wk") · pace indicator · streak chip · quick-log button. Long-press Edit/Pause/Delete; paused habits sink to a gray collapsed group (excluded from scoring). Empty: explainer of the 3 types + Create.

**Habit Detail [S1]**: header + Edit → **This-week card** (weekly: big "3 / 5" + pace bar + "On pace — 2 more by Sunday"; planned-days row Mon–Sun: planned outlined, completed filled green wherever they happened, swapped day gets a small tick, missed planned day = neutral outline never red; caption "Planned days are suggestions — only the weekly total counts") or **Today card** (rep pips "1 of 2 today") → stats tiles (Current streak · Best · 30-day % · Total, mono) → **month calendar** (§B5.3, weekly habits add a per-week ✓/—/live-fraction strip at each row's right edge) → reverse-chron history list, rows tap-editable (the manual backfill/correction mechanism).

**Habit Editor [S1]** (sheet): Name · SF Symbol icon grid · Area picker · Type segmented (Daily / Multiple per day / Weekly target) morphing the form (reps stepper 2–10, weekly stepper 1–7 + "Suggested days (never penalized)" toggles) · Start date · Archive-on-delete warning.

**Settings [S1]**: Account (email, change password, sign out) · Appearance (System/Light/Dark) · Scoring (weights + boundary + week start, display-only "managed on server") · Plan [S2+]: Restart interview, Edit vision; minimal manual Goals/Areas editor lives here in S1 for task-linking · About.

**Onboarding Interview [S2]** — full-screen; see B6.

**Plan Proposal Review [S2]** — follows interview; nothing is created until Approve. Vision recap card (editable) → goal cards (2–4: title, area chip, measurable target line, collapsible **Weekly tactics** + **Suggested habits & tasks** — each row has type badge HABIT/TASK/RECURRING, config summary, ✎ opens the standard editor prefilled, ✕ removes; "+ Add" rows) → per-card overflow: Remove goal / "Ask AI to revise" (inline instruction → that card shimmer-regenerates). Pinned footer: **Approve plan** + live caption "Creates 3 goals, 7 habits, 4 recurring tasks" + start-Monday chooser. Removing everything disables Approve.

**Vision [S2]**: document-like page — AI-composed statement (editable), per-area aspiration cards linking to filtered Goals, "Revisit in interview" mini-interview. Empty: "Start interview" / "Write manually".

**Block Overview [S2]** (Plan tab root): block header + **13-square week strip** (1–12 + R; past squares tinted by that week's avg score — gray <50 / amber 50–69 / green ≥70, the universal score bands; current outlined accent with live fill; R violet). Tap square → Week Detail. → Goal cards (title, area chip, progress bar from tactics/tasks + manual override, status pill On track/At risk/Done, current-week tactic line) → This-week card (tactics checklist, avg score vs last week "78 ▲6"). Empty: "Start onboarding interview" / manual goal editor.

**Goal Detail [S2]**: target statement → progress bar + manual override slider → tactics by week (12 rows, current highlighted, expandable checkboxes) → linked habits (mini pace chips) → linked tasks (open/done) → notes. Overflow: Edit / Mark done / Abandon (history kept, gray).

**Week Detail [S2]**: "Week 7 · Jul 7–13" → seven day-score dots (tap → historical breakdown) → tactics checklist → tasks completed → per-habit week results. Past weeks read-only; S4 adds the review-notes block.

**Chat [S3]**: transcript + input bar (Mac: ⌘↩ send). User bubbles right accent-subtle; AI messages plain-on-canvas left with 20 pt avatar dot. Streaming with transient tool-status lines ("Reading your week…") that collapse into the finished message. **Action cards**: type badge (NEW TASK / EDIT HABIT / …), labeled fields (edits show old→new diffs), **Confirm** / Dismiss, ✎ opens native editor prefilled (saving = confirm). Related actions batch: "Confirm all (3)" + per-row confirms. Confirmed → compressed green state, tappable link to the object; stale pending cards flag "data may have changed". Read-only answers may embed native mini-visuals (score bars, pace chips). Empty state: suggestion chips ("Plan my day", "How is this week going?", "Add a task", "I'm feeling off today"). Conversation history list via overflow.

**Weekly Review [S4]** (full-screen; banner on Today Sunday 17:00 → Monday EOD, also launchable from Block Overview; skippable without guilt copy): 1) recap deck — 3 swipeable stat cards (week scores; habits met/missed + streak changes; goals/tactics); 2) 3–5 reflective interview-style questions (~8 exchanges max); 3) AI adjustment proposals as standard action cards; 4) close screen with stored AI summary → Week Detail.

**Week 13 [S4]** (automatic): Today gets violet "Review Week" chrome; tasks section → "tasks are paused" (hidden not deleted; date-critical recurring tasks can opt out of pausing per-template, shown under "Scheduled anyway"); score = habits+feel renormalized (67/33) with breakdown caption. Block Overview shows "Start retrospective": 1) recap deck ×5 (12-week score line · goal outcomes · per-habit 12-week heat strips · body deltas + first/last photo pair · stat grid); 2) retro conversation (per-goal "what happened?", keep/drop); 3) short re-onboarding (~8–12 questions, prefilled "Keep, modify, or replace?" options per area); 4) Plan Proposal Review → approve → Block n+1 starts next Monday. Unfinished by Sunday → between-blocks state (habits+feel scoring continues, persistent "Next block not planned yet" banner).

**Trends [S4; 7-day bars ship S1 in Score Breakdown]**: range 7/30/90 → daily score chart (7d bars tinted by band, today outlined; 30/90 raw line 30% opacity + 7-day moving average, fixed 0–100 axis, faint band zones) → weekly averages card (delta + 8-week mini columns) → component split as three small multiples → habit consistency heatmap (rows = habits, 30 day-columns, calendar-dot language). Tap any day → historical breakdown.

**Body — Metrics [S4]**: card per user-defined metric type (new: name, unit, decimals, optional goal value+direction): latest value + date, 90 d sparkline, 30 d delta. Tap → full chart (goal line dashed, entry list, swipe edit/delete). "+ Log" → numeric sheet (value + date, decimal pad).

**Body — Photos [S4]**: month-grouped timeline, 88 pt thumbnails with angle chips (user-defined labels, reused); add via camera/library + date + angles. **Compare**: two dates (default earliest vs latest), same-angle side-by-side with draggable center divider, "84 days apart" caption, angle switcher, lockstep pinch-zoom. Empty: "Your first photo is the baseline."

## B4. Key flows

- **First run [S2+]**: create account → full-screen interview (no tab bar) → "Building your 12-week plan" takeover (rotating status lines, 10–30 s) → Plan Proposal Review → edit/approve → Today with welcome briefing. (S1 first run: account → empty Today hero.)
- **Daily loop**: open → ring animates, briefing expanded, mood tinted; backfill yesterday's mood if shown → work the lists (each completion nudges the ring live) → evening wrap-up banner → set feel → done. Post-midnight actions count for the same day until 3 AM.
- **Multi-rep habit**: tap → pips ●○ "1 of 2 · 50%" (contributes 50% immediately); stays in active list until full; full → completed group + solid calendar dot. Streak counts only 100% days. Mis-tap → long-press Undo.
- **Gym day swap**: unplanned day → habit sits in "Also available" → log → promotes, pace chip recomputes "3/5 · on pace". No prompt to change the plan; planned days edited only in the Habit Editor.
- **Task via chat**: "remind me to send the investor update every first Monday, high priority" → status line "Creating recurring task…" → NEW RECURRING TASK card (Title/Repeat/Next/Priority) → user taps ✎, adds Goal link, saves (= confirm) → card collapses to link → AI: "Done. It'll appear on Today each first Monday." ("never mind" before confirm → AI dismisses its own card.)

## B5. Visualization specs

1. **Score ring**: one ring, three arcs sized by weight (tasks 144° indigo · habits 144° green · feel 72° mood-tint), 4° gaps, each arc fills by its component %; track bg.subtle; center = 44 pt score + "today". Mood unset → feel arc dashed + score shows "°" affix ("mood not set"). You can read *why* the score is low from which arc is short. 0.6 s spring on change; historical rings static.
2. **Habit rows**: daily = circle check; multi-rep = 8 pt rep pips + "+1" capsule + fraction; weekly = **pace capsule** — n segments (n = weekly target) filling green, with a thin vertical **pace tick** at `target × elapsed/7` ("where you should be by tonight"): fill ≥ tick = "On pace", short = amber "2 behind" (segments up to tick tinted warning), met = "Week ✓" (solid). **Never red**; mathematically-impossible week = gray "Out of reach". Display rule: elapsed excludes today before 18:00.
3. **Calendar dots** (10 pt, Monday-first, 3 AM boundary): solid green = full; **pie-fill by exact fraction** = partial (1/2 = half-pie); hairline outline = applicable but nothing logged (neutral, never red); blank = N/A. Weekly habits: logged days solid + per-week ✓/—/live-fraction result strip. Today = accent ring. Tiny legend row.
4. **Streaks**: flame + mono count + unit ("12 days" / "6 weeks"); weekly streaks ignore the in-progress week unless already met; broken streak shows grayed "ended" for 7 days; hidden below 2 (no "1 day streak" noise); no loss alarms.
5. **Charts**: Swift Charts; universal score bands gray/amber/green; tap-through everywhere to that day's breakdown.

## B6. Interview UI (used by onboarding, weekly-review Q&A, week-13 re-onboarding, vision revisit)

Full-screen, resumable ("Save & exit"; draft banner on next launch). **Progress = 6 named phases** (dot-stepper: About you → Life areas → Your vision → This block's goals → Habits & routines → Wrap-up), never a percentage (unlimited follow-ups would make it dishonest). AI announces phase transitions, rendered as divider rows. One question at a time; prior Q&A scrolls above as dimmed transcript. Question card: streamed title2 question + optional context line; follow-ups carry a small "follow-up" tag; MC option rows (radio vs "Select all that apply" squares) + **always** a "✎ Write my own" expanding text field (combinable with multi-select); Continue pinned bottom; AI-designated questions show tertiary Skip. Thinking state: 3 shimmer lines + rotating verbs; >6 s adds "Still thinking — good answers take a moment." Anti-endless: phase cap, ~3 follow-ups per topic, after ~10 min a quiet "Ready to see your plan?" fast-forward chip, wrap-up always ends "Anything else I should know?". **Tone: literal, concrete, autism-friendly — every abstract question ships example options; no vague vibes-questions.** Mac: centered 560 pt column, ↑↓/Return + number-key selection.

---

# Part C — Staged build checklist & verification

## Stage 0 — Scaffolding
- pnpm workspace + turbo.json + `.gitignore` (ignore `.xcodeproj`, `.env*`); `apps/api` via `create-next-app` (App Router, TS, no UI deps); Drizzle + drizzle-kit + Zod + vitest; `apps/app` via XcodeGen `project.yml` + empty SPM packages (JarvisAPI, DesignSystem); `docs/spec.md` = this plan; README with dev workflow.
- Verify: `pnpm --filter api dev` serves a health route; `xcodegen generate` builds an empty app for both iOS 26 sim and macOS.

## Stage 1 — Core tracking loop
- Schema: users, sessions, settings, areas, tasks, recurrence_templates, habits, habit_completions, mood_entries, daily_scores (goalId/areaId columns shipped nullable now → zero-migration Stage 2 linking).
- API: auth, settings, days/today + historical + scores, tasks + templates, habits + calendar/stats, mood. Scoring engine + daykey + recurrence with **vitest coverage first** (pace/reconciliation, 3 AM boundary incl. DST dates, renormalization, subtask fractions, retro-credit of late completions).
- App: Login, Today (ring, breakdown, mood + backfill, overdue/tasks/habits sections), Tasks (list/detail/editor/recurrence), Habits (list/detail/calendar/editor), Settings (+ minimal Areas/Goals editor), 7-day bars in breakdown. Both platforms' navigation shells.
- Verify: create habits of all 3 types, log across a week boundary, confirm reconciliation makes a back-loaded gym week score identically to an on-plan week; complete a task after its due date and confirm the historical day retro-credits; set mood after midnight and confirm 3 AM attribution.

## Stage 2 — 12 Week Year + AI onboarding
- Schema: vision, blocks, goals(+trackStatus,+manualProgress), tactics, tactic_completions, user_profile, interview_sessions.
- API: vision/blocks/goals/tactics, `ai/interview/*`; AI provider + tiers (api_key mode; codex_oauth experiment after, with automatic fallback).
- App: Interview flow, Plan Proposal Review, Plan tab (Vision, Block Overview + week strip, Goal Detail, Week Detail), week chip on Today.
- Verify: run a full interview → approve → block/goals/habits/tasks exist and Today reflects them; "Ask AI to revise" regenerates one card; nothing persists before Approve.

## Stage 3 — Chat agent + briefings
- Schema: conversations, messages, proposed_actions, briefings.
- API: `ai/chat` SSE, conversations, action confirm/reject, briefing (advisory-lock cached).
- App: Chat tab (+ Mac slide-over ⇧⌘J), streaming, action cards (single + batch + stale detection), Briefing card, evening wrap-up banner.
- Verify: end-to-end "add a recurring task" via chat incl. ✎-edit-as-confirm; reject path feeds the model; briefing generated once per dayKey (double-open race).

## Stage 4 — Reviews, week 13, body, trends
- Schema: metric_types, metric_entries, progress_photos.
- API: weekly review start/close, scores/weekly, metrics, photos (Blob upload-url/confirm/signed GET).
- App: Weekly Review flow + Today banner, Week-13 mode (paused tasks, 67/33 scoring, violet chrome) + retrospective + re-onboarding → next block, Trends page, Body metrics + photos + compare.
- Verify: simulate a block at week 13 (adjust block dates in DB) and walk the full retro → next-block flow; upload/compare photos; confirm review-week scores renormalize.

## Open items (to resolve during build, not blockers)
1. **Model IDs**: verify the exact published OpenAI model IDs for "GPT-5.6 Luna" (+ mini variant) at build time; they are env values only.
2. **Codex-subscription auth**: experiment (§A5) after api_key mode works; accept it may be unusable (ToS/endpoint stability) — fallback is automatic.
3. Physical-iPhone dev against localhost needs the Mac's LAN IP in Debug.xcconfig.

## Manual checkpoints for Siebe (per workflow preference — the agent stops and gives instructions)
- Stage 0: create NeonDB project + dev branch, Vercel project + Blob store, put secrets in Enkryptify.
- Stage 2: provide OpenAI API key (and optionally Codex tokens for the experiment).
- Each stage end: run the app on iPhone + Mac and sign off before the next stage.
