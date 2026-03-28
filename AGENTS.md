# Signals

AI health coach — HealthKit data + markdown training plans + LLM coaching.

## Rules

1. **Read before you write.** Check the docs below before making architectural or convention decisions. The answer is probably already documented.
2. **Update docs before committing.** If your changes affect architecture, conventions, or deployment, update the relevant doc file in the same commit.
3. **Run linters before committing.** `standardrb` and `brakeman` must pass (enforced by Lefthook git hooks).
6. **Keep "What's next" current.** Update the section below before committing if the project's next step has changed.
4. **Keep commits small and focused.** One logical change per commit.
5. **Follow tool conventions.** If you're fighting a tool, stop and reassess — wrong tool or wrong approach.

## Documentation

| File | When to read |
|------|-------------|
| [docs/background.md](docs/background.md) | Understanding the product vision, roadmap, and domain |
| [docs/architecture.md](docs/architecture.md) | Making technical decisions, adding dependencies, changing data flow |
| [docs/conventions.md](docs/conventions.md) | Writing code, tests, views, or commits |
| [docs/setup.md](docs/setup.md) | Setting up a new development machine |
| [docs/deployment.md](docs/deployment.md) | Changing infrastructure, env vars, or deploy process |
| [docs/plans/](docs/plans/) | Design docs and implementation plans for each feature slice |

## What's next

Phase 1 Slice 2 (webhook endpoint, health data tables, data pipeline, dashboard) is complete and deployed on Render. Historical data (30 days) is seeded from CSV on deploy. Health Auto Export is configured with "Previous 7 Days" + Day grouping for ongoing sync, plus a "Yesterday" automation as a safety net. Data uses replace semantics — latest payload for a given day always wins. Next up is **Phase 2: training plans + Today view**.
