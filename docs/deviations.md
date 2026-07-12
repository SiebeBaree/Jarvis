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
