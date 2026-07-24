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
