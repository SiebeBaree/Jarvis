# Jarvis

Personal J.A.R.V.I.S.-style life assistant: 12 Week Year planning, daily scoring, habit tracking, and an AI companion. Single-user, online-only.

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

## Build stages

1. **Stage 1 — Core tracking**: auth, tasks (subtasks + recurrence), habits (daily / N×day / N×week with pace scoring), Today page with daily score + mood.
2. **Stage 2 — 12 Week Year + AI onboarding**: vision, blocks, goals, tactics, AI interview → plan generation.
3. **Stage 3 — Chat agent + briefings**: tool-use chat with confirmable action cards, morning briefing.
4. **Stage 4 — Reviews & body**: weekly reviews, week-13 retrospective, metrics, progress photos, trends.
