# Known deviations from docs/spec.md (v1)

Reviewed and accepted at the 2026-07-10 pre-production audit. Everything here is a
conscious v1 simplification, not an oversight. Candidates for a v1.1 polish pass.

## Product / UX

| Area | Deviation | Rationale |
|---|---|---|
| Action cards | One-line server-templated summary instead of labeled field rows with old→new diffs; confirmed cards are not tap-through links; no stale-pending flag; no batch "Confirm all"; no ✎-edit-as-confirm | `args` are intentionally opaque to the client; summaries carry the essentials. Revisit when cards prove insufficient in real use |
| Chat | Read-only answers render as text only — no embedded native mini-charts | Model describes numbers well; visuals live one tab away |
| Interview | Whole round (1–3 questions) shown at once instead of strictly one-at-a-time; no ~10-min "Ready to see your plan?" fast-forward chip; no draft banner on Today; no Mac ↑↓/number-key selection | Round-at-once is arguably better UX for 1–3 related questions; resume works silently |
| Plan review | AI-proposed plans cannot contain recurring tasks (one-off starters only); ✎ opens lightweight sheets, not the full standard editors; "Ask AI to revise" per-card regeneration not built | Recurring obligations are easy to add in Tasks after apply |
| Weekly review | Conversation phase is free chat, not the structured interview UI | The review protocol (observations → questions one at a time) is enforced by the model prompt instead |
| Week-13 recap deck | Habit card shows block totals, not per-habit 12-week heat strips; body card shows metric deltas without the first/last photo pair | Data pressure vs. build cost; heat strips are v1.1 |
| Week Detail | No per-habit week results section; review-notes (stored outcome) not surfaced there | Outcome lives on the review close screen + conversation history |
| Vision | No "Revisit in interview" mini-interview; area cards don't navigate to filtered Goals | Vision edits are manual; full re-interview exists via Settings |
| Tasks on macOS | List + inspector instead of a sortable NSTable-style Table with drag-between-groups | Inspector pattern kept; Table is v1.1 |
| Habits on macOS | Detail pushes instead of a 320pt inspector | Consistent with in-app navigation |
| Settings | No change-password (no endpoint either — reset via DB if ever needed); Plan section lacks "Edit vision" shortcut | Single user, password known; vision editable in Plan tab |
| Streaks | "Ended streak grayed for 7 days" not shown (server doesn't expose broken-streak metadata) | Needs a `previous` field in the stats response first |
| Offline | No dedicated full-screen "You're offline" panel; failures show inline error + retry | Online-only app; inline retry covers it |
| Wrap-up banner | "Set my feel" is a caption pointing at the mood card, not a scroll-to action | Mood card sits directly above the banner |
| Photos | Library import only (no in-app camera capture); compare has divider drag but no lockstep pinch-zoom | PhotosPicker covers the flow; camera is v1.1 |
| Metrics | Entry rows delete via button (not swipe); edit = re-log the same date (upsert) | Functional equivalents |
| Design tokens | No dedicated violet token — review-week chrome uses the indigo accent; week-strip current square has outline but no live partial fill; score number lacks the "°" affix when mood is unset (dashed arc communicates it) | Cosmetic |
| Trends heatmap | Current calendar month instead of trailing 30 days; partial days at reduced opacity instead of pie-fill dots | Cosmetic |
| First-run | Auto-interview triggers on fresh registration; existing accounts use the Today/Plan banners | Account already existed before Stage 2 shipped |

## Technical

| Area | Deviation | Rationale |
|---|---|---|
| Photos API | Raw-bytes `POST /photos` through the function (4 MB cap, client compresses) instead of `upload-url` + `confirm` client-upload flow | Simpler; photos are ~1–2 MB after compression. Store is PRIVATE with presigned reads (stronger than spec) |
| apply-plan atomicity | neon-http has no transactions; apply uses sequential inserts with compensating cleanup on failure instead of a real transaction | Driver limitation; cleanup keeps retries safe |
| Briefing dedup | Row-claim upsert instead of `pg_advisory_xact_lock` (session locks don't survive HTTP pooling) | Same guarantee in practice |
| AI card dismissal | The model cannot withdraw its own pending cards (no dismiss tool); user dismisses via the card | Rarely needed; revisit with real usage |
| Review seeding | Habit applicability computed at week end — habits archived mid-week or created mid-block can skew seeded review stats slightly | Model narrative only; scores are correct |
| Client day math | DayKeyMath uses the device timezone; correct at home (Europe/Brussels), can skew grouping while traveling. Server-persisted dayKeys unaffected | Bounded, self-corrects on return |
| Sessions | Bearer tokens never expire (revoke via sign-out) | Single user, Keychain storage |
| SSE maxDuration | 180 s (spec said 120) to accommodate deep-tier review turns | Deliberate |
| Codex auth | `codex_oauth` mode not implemented; api_key with automatic fallback plumbing in place | Flagged experiment; OpenAI API works |
| Code duplication | ReviewChatView duplicates a minimal action card; ScoreBands mirrors PlanDisplay helpers | Flagged for a /simplify pass |

## 2026-07-12 redesign — "You author, AI knows you"

Product pivot after the first real onboarding run (interview produced a plan
of the co-founder's commercial tasks; no way to correct it; personal
improvement areas never asked about). Decisions confirmed with the user:

- **AI-generated plans removed entirely.** `lib/ai/interview.ts`,
  `lib/ai/apply-plan.ts`, all `/ai/interview/*` routes, and the Swift
  Onboarding feature are deleted. The user authors areas/blocks/goals/habits
  in a new manual **Setup Wizard** (`Features/Setup/`). The `interview_sessions`
  table remains for history but nothing reads or writes it.
- **Seeding conversations** (`conversation_kind = 'seeding'`): a plan-free
  get-to-know-you chat launched from the wizard; the model saves memories via
  the inline `save_memory` tool and is instructed to never propose plan items.
- **Growing AI memory** (`memories` table): one durable fact per row, seven
  fixed categories. Auto-extraction runs after every chat turn via
  `next/server after()` (`lib/ai/memory.ts`), best-effort. Full CRUD at
  `/memories`; Swift Memory screen under Settings → "What J.A.R.V.I.S. knows".
  `user_profile` is legacy: still shown in context when present, never written.
- **Improvement areas + weekly photo check-ins** (`improvement_areas`,
  `area_checkins`): one photo per area per ISO week (weekKey = Monday),
  private Vercel Blob, AI vision commentary generated async after upload
  (`lib/ai/checkin-commentary.ts`, deep tier). Weekly prompt is an in-app
  Today card (no push). Check-ins deliberately do NOT affect the daily score.
- **Account reset**: `POST /account/reset` (confirm literal required) wipes
  all domain rows + blobs, keeps users/sessions/settings. Settings → Danger
  zone; re-runs the setup wizard afterwards.
- Scoring, mood (one 0–100/day), Trends, Tasks, Habits, Body are unchanged.
- E2E-verified 2026-07-12 (wizard flows, check-in upload + vision commentary,
  seeding memories, post-turn extraction, memory-grounded answers, reset).

## 2026-07-21 — task categories, habit backfill strip, single-arc score ring

- **Task categories** (`task_categories` table + `categoryId` on tasks and
  recurrence templates): TickTick-style lists (work/personal/household...),
  purely organizational, never enter scoring. CRUD at `/task-categories`;
  filter chips ("pages") in the Tasks tab; pickers in the task editor, task
  detail, quick-add composer, and recurring-template editor. Deleting a
  category keeps its tasks (FK `set null`). Deliberately separate from
  `areas` (life areas stay a 12WY concept).
- **Habit backfill strip**: the Today payload's habit entries now carry
  `recentDays` (trailing 7 days of reps); habit cards in the Habits tab show
  a tappable 7-day strip so forgotten days can be checked off up to a week
  later. `POST /habits/:id/log {dayKey}` already existed; the server
  recomputes (and re-finalizes) that day's score on backfill.
- **Score ring redrawn as a single arc** (deviation from spec §B5.1's
  three-arc ring): scoring math is untouched (renormalization stays); only
  the display changed. The ring now draws one continuous arc from 12
  o'clock filling total%, because the three weight-proportional arcs made a
  partial day read as disconnected green fragments. The per-component
  detail lives in the bars next to the ring and in the breakdown sheet.

## 2026-07-24 — morning briefing removed, latency work, Tasks tab trimmed

- **Morning briefing deleted** (spec §B3 Today item 2): the card fired an LLM
  call (`GET /ai/briefing/today`) on every Today load, and that call itself
  rebuilt the whole day payload — it dominated the screen's latency for a
  card that wasn't being read. View, endpoint, client method and route are
  gone; `lib/ai/briefing.ts` now only serves the evening wrap-up
  (`getBriefing(kind)` → `getWrapup`). The `briefings` table keeps its
  `morning` enum value so old rows still decode.
- **Request latency.** Over the Neon HTTP driver every query is a round-trip,
  so the work was removing round-trips from the serial path:
  - `requireAuth` loads session + user + settings in ONE joined query
    (was three sequential `findFirst`s, on *every* request).
  - `buildDayPayload` no longer re-reads what it already has: the block,
    habits, reps and mood it fetches are handed to `recomputeDay` via its new
    optional `prefetched` argument (they used to be queried twice), the two
    `withSubtasks` calls collapsed into one query covering due + overdue, the
    two `repCounts` windows became one query sliced in memory, and the
    upcoming-block lookup joined the parallel batch.
  - `materializeTemplates` batches its inserts/updates instead of looping
    with awaits per template.
  - `GET /tasks/:id` added — the task detail screen used to fetch the entire
    "all" list (then "done") to find one row.
  - `maxDuration = 30` on `/days/today` and `/tasks` so a cold lambda waking
    a suspended Neon compute isn't cut off mid-request.
- **Client.** GETs retry transient failures (network error, 5xx, 408, 429)
  twice with backoff — that is what the "failed to fetch, tap Retry" on first
  launch was. Today's payload is also cached on disk and painted immediately
  on a cold launch (same dayKey only) while the refresh runs behind it.
  Post-mutation revalidation is debounced (700 ms) instead of one full
  `/days/today` per tap, Tasks reschedule/delete became optimistic, and the
  stores coalesce concurrent fetches.
- **Today list identity.** Every task/habit `ForEach` now sits at a fixed
  position in the List's ViewBuilder (empty collections render nothing)
  instead of inside `if` blocks. Wrapping one in a conditional made SwiftUI
  fall back to structural row identity, so completing an overdue task
  animated the row *below* it out instead.
- **Mood card compacted**: one caption line ("How do you feel?" + word label
  + value) over a 4pt track, ~30% shorter than the old headline-sized card.
- **Tasks tab**: inline search and the ⋯ → "Recurring tasks" toolbar menu
  removed. Recurring templates stay reachable from a generated task's detail
  screen.

## 2026-07-25 — local-first client, editable block dates, goals in the Plan tab

- **The client is now local-first.** `RequestCache` (in-memory, wiped whole on
  every mutation) is replaced by `LocalStore`: a disk-backed cache that never
  evicts, so screens paint from the last known state instead of a spinner, and
  invalidation is per-`Entity` — completing a task no longer forces habits, the
  plan and the vision to refetch. Reads are stale-while-revalidate everywhere.
- **Writes never block the UI.** `MutationQueue` is a durable outbox: a
  mutation is applied to local state, persisted to
  `Application Support/Jarvis/outbox.json`, and flushed in the background,
  draining FIFO with exponential backoff and an `NWPathMonitor` trigger so
  reconnecting flushes immediately. A change made offline (or with the app
  killed mid-flight) survives relaunch. `SyncStatusBar` surfaces pending or
  failed writes; a normal flush stays silent (2 s grace).
- **Replay safety is the constraint that shaped the API.** A queued request may
  be sent twice, so `POST /tasks` and `POST /habits/:id/log` now take
  client-generated ids (`id`, `completionId`) and upsert on them —
  habit logging inserts a row, so without this a replay silently double-counted.
  A replayed create returns 200 with the existing row instead of 201; a
  cross-user id collision is 409 `id_conflict`. Patches send absolute values,
  and a DELETE/PATCH that 404s on replay counts as already applied.
  This is what makes creation instant: the row renders with the id it will keep,
  so it is completable and editable before the request has been sent.
- **Block start dates are editable** — this reverses the original
  "dates are immutable once created" decision in `blockPatchSchema`. Moving a
  block snaps to Monday, re-derives `endDate` and `status`, rejects overlaps
  with other blocks (409), and rescores only the days that already have a
  `daily_scores` row in the old ∪ new range. The Plan tab exposes it (and the
  block title) behind the slider icon in the block header. Rationale: a block
  started before the user was actually ready burned real weeks with no recourse.
- **Goals can be added from the Plan tab.** `GoalsEditorView` in Settings
  creates goals with no `blockId`, which the Plan tab (which lists a block's
  goals) never showed — so there was no way to add a goal to the running block.
  The new sheet always attaches the current block.
- `POST /blocks/:id` PATCH, `POST /goals` with `blockId`, `GET /tasks/:id`, and
  both idempotent creates were verified against the real API (14 checks) with a
  throwaway block and session, all cleaned up afterwards.

## 2026-07-25 — Trends: readable weekly average, components rewritten, sized heat dots

- **Weekly average showed "—" whenever today fell outside a block week.**
  `loadWeekly` picked the block week containing today and gave up if there was
  none, so a block that had not started yet (or had ended, or a gap between
  blocks) blanked the card even though scores existed. It now falls back to
  plain calendar weeks in all of those cases. The mini chart also drops leading
  weeks with no data — eight mostly-empty columns crowded the axis labels — and
  annotates each bar with its value.
- **"Components" replaced by "What's driving your score".** Three sparklines
  with hidden axes and no numbers conveyed nothing. Each part is now a row:
  average points per scored day, the weight it is out of, the percentage, and a
  proportion bar — so the weakest component is obvious. Weights come from
  `settings.scoreWeights`, matching the Today score card.
- **Habit-consistency dots are derived from the available width** rather than a
  fixed 8pt, which stopped short of the trailing edge on iPhone and used barely
  half the card on Mac. `HeatDotMetrics` (in DesignSystem, next to the other
  layout tokens) computes the largest dot that fits a month on one row, with
  spacing proportional to the dot: ~9pt on iPhone and ~18pt on Mac for a 31-day
  month, both flush to the edges. A phone is genuinely width-bound here — 31
  dots in 338pt cannot go far past 9pt. Added a legend, since the four dot
  states (done / partial / missed / not due) were otherwise unexplained.
- **Debug-only `-jarvisToken <raw>` launch argument** seeds the session on
  launch. Reinstalling on the simulator clears its keychain, so every rebuild
  landed on the sign-in screen; this attaches an already-created session
  instead. `#if DEBUG` only — never compiled into Release. Create the session
  with an insert into `sessions` (sha256 of the raw token), then
  `xcrun simctl launch <udid> com.siebebaree.jarvis -jarvisToken <raw>`.

## 2026-07-29 — AI and the 12 Week Year removed; goals rebuilt

The app was not doing its job: planning ceremony and an AI companion were in the
way of the thing it exists for, which is showing whether the day was executed.
Everything below is a deliberate departure from `docs/spec.md`, which still
describes the old design.

- **All AI features deleted.** Chat, the tool-use agent, action cards, morning
  briefings and evening wrap-ups, weekly-review conversations, the onboarding
  interview, the AI memory table, and the improvement-area photo commentary.
  Gone from the schema (`conversations`, `messages`, `proposed_actions`,
  `briefings`, `memories`, `user_profile`, `interview_sessions`,
  `settings.ai_overrides`, `area_checkins.ai_*`), from the API (`/ai/**`,
  `/memories`), and from the app (`Features/Chat`, `Features/Reviews`,
  `MemoryView`, the SSE client). The `openai` dependency is no longer used.
- **The 12 Week Year layer deleted.** Vision, blocks, tactics, tactic
  completions, weekly reviews, the Plan tab and the setup wizard. The daily
  score is now simply tasks + habits + feel on every day — `isReviewWeek` is
  gone from the engine, from `daily_scores`, and from the Today payload, and
  week 13 no longer pauses tasks. Trends always computes calendar-week
  averages, which it already had as a fallback.
- **Goals rebuilt around a deadline instead of a block.** The old `goals` table
  (block-scoped, progress derived from tactics) is dropped and replaced. A goal
  now carries a horizon (short/long), a start and target date, and optionally a
  numeric range (`start_value` → `target_value` with a unit) plus a milestone
  checklist. Progress is the numeric fraction when a range is set, else the
  fraction of milestones done, else absent. It is always shown against
  *time* progress — the gap between the two bars is the entire point of the
  tab. Numeric progress is measured from the baseline so a downward goal
  (92 → 80 kg) reads identically to an upward one.
- **Tasks and habits no longer link to a goal.** `goal_id` is dropped from
  `tasks`, `habits`, and `recurrence_templates`, and the goal pickers are gone
  from the task editor, task detail, and recurring-task editor. Goals are what
  you're aiming at; tasks and habits are what you did today. Tying them made
  every task-creation flow ask a question the user didn't want to answer.
- **Today pages back three days.** A horizontal pager covers today and the
  three days behind it, with a segmented strip above it (each day's score) so
  the gesture is discoverable. Every page can set its feel score and log or
  unlog habits; tasks are read-only on past days, since those days are already
  scored and back-dating a completion rewrites history rather than recording
  it. This replaces the old "yesterday's feel?" backfill row, which only
  covered one day and only before noon.
- **Optimistic habit updates no longer flicker.** Two taps in quick succession
  showed both reps, then dropped one, then brought it back. Two races caused
  it: `onLanded` scheduled a revalidation as soon as the *first* write landed,
  while the second was still in flight, and a `GET` already in flight when a
  tap happened would overwrite the optimistic state with a response that
  predated it. Fixed with `AppModel.writeTicket` — every local write bumps it,
  every store captures it before fetching and discards a response if it moved —
  and by holding revalidation until the outbox has actually drained (bounded,
  so an offline queue can't wedge it). Habit stats no longer blank out on
  mutation either; the stale value stays until its replacement arrives.
