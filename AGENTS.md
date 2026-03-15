# Signals

AI health coach — HealthKit data + markdown training plans + LLM coaching.

## Rules

1. **Read before you write.** Check the docs below before making architectural or convention decisions. The answer is probably already documented.
2. **Update docs before committing.** If your changes affect architecture, conventions, or deployment, update the relevant doc file in the same commit.
3. **Run linters before committing.** `bin/rubocop`, `bin/standardrb`, `bin/brakeman` must all pass.
4. **Keep commits small and focused.** One logical change per commit.
5. **Follow tool conventions.** If you're fighting a tool, stop and reassess — wrong tool or wrong approach.

## Documentation

| File | When to read |
|------|-------------|
| [docs/background.md](docs/background.md) | Understanding the product vision, roadmap, and domain |
| [docs/architecture.md](docs/architecture.md) | Making technical decisions, adding dependencies, changing data flow |
| [docs/conventions.md](docs/conventions.md) | Writing code, tests, views, or commits |
| [docs/deployment.md](docs/deployment.md) | Changing infrastructure, env vars, or deploy process |
| [docs/plans/](docs/plans/) | Design docs and implementation plans for each feature slice |
