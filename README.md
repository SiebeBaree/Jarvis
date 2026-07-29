# Jarvis

Personal discipline tracker: goals with a clock against them, daily scoring, tasks and habit tracking. Single-user, online-only, no AI.

Full product + technical spec: [docs/spec.md](docs/spec.md).

## Layout

- `apps/api` — Next.js API (App Router route handlers only), deployed on Vercel. Postgres on NeonDB via Drizzle.
- `apps/app` — SwiftUI multiplatform app (iPhone iOS 26 + macOS 26), generated with XcodeGen.

## Development

### API

```sh
pnpm install
pnpm --filter api dev            # http://localhost:3000 (use `ek run` for secrets)
pnpm --filter api test           # vitest (scoring engine, daykey math, recurrence)
pnpm --filter api db:generate    # generate SQL migration from schema changes
pnpm --filter api db:migrate     # apply migrations (needs DATABASE_URL)
```

Secrets are managed with Enkryptify (`ek run -- pnpm --filter api dev`). See `.env.example` for the full list. NeonDB: `main` branch = prod, `dev` branch = local development.

### App

```sh
brew install xcodegen
cd apps/app
xcodegen generate
open Jarvis.xcodeproj
```

The `.xcodeproj` is generated and gitignored — all project config lives in `apps/app/project.yml`. Debug builds point at `http://localhost:3000` (see `apps/app/Config/Debug.xcconfig`; use the Mac's LAN IP for a physical iPhone). Release points at the Vercel deployment.

## What's in it

- **Today** — the daily score (tasks / habits / feel), swipeable back three days so a
  day you forgot to rate is still ratable tomorrow.
- **Tasks** — subtasks, priorities, categories, recurrence templates.
- **Habits** — daily, N×day, and N×week with pace scoring and streaks.
- **Goals** — short- and long-term goals, each showing how much of the time has run
  against how much of the goal is done. Progress comes from a numeric target
  (0 → 10k, 92 → 80 kg) or from milestones ticked off.
- **Trends / Body / Improve** — score history, body metrics, weekly photo check-ins.
