# Conventions

## Code style

- **Standard Ruby** (`standardrb`) for formatting and linting. Replaces RuboCop-omakase — `.rubocop.yml` inherits from Standard so both commands use the same rules.
- **Brakeman** for security scanning. Run `bin/brakeman` to check manually.

## Git hooks (Lefthook)

Hooks are defined in `lefthook.yml` and installed automatically via `bin/setup`.

**Pre-commit (runs on every commit):**
- `standardrb --fix` on staged `.rb` files (auto-fixes and re-stages)
- Prints a reminder to consider updating docs/tests if non-doc files are staged

**Pre-push (runs before push):**
- `brakeman` — blocks push on security warnings
- `bin/rails test` — blocks push on test failure

To install hooks manually: `bundle exec lefthook install`

## Testing

- **Unit and integration tests** are the primary testing layers.
- **Minimal view-level tests.** Don't test markup unless it encodes important logic. Smoke tests only — assert pages render successfully and contain key content. Never assert specific CSS classes or HTML structure.
- **Every test should have clear value.** Prefer a smaller, smarter test suite over comprehensive-but-redundant coverage. If a test doesn't catch a meaningful failure, delete it.
- **No excessive mocking.** Test real behavior wherever practical.
- Run tests: `bin/rails test`

## Frontend

- **Tailwind CSS only.** No custom CSS unless absolutely unavoidable. Use Tailwind v4 defaults — no custom config file.
- **Dark mode is forced** via `<html class="dark">` and `@custom-variant dark` in `application.css`. All views must work on a dark (`bg-zinc-900`) background. Use `zinc` for neutral tones (zinc-100 for text, zinc-400 for muted, zinc-800 for surfaces).
- **Mobile-first.** Base styles target iPhone. Use `md:` and `lg:` breakpoints to scale up for larger screens. Prefer stacked layouts on mobile over cramped tables or grids.
- **ViewComponents** for reusable UI patterns. Place components in `app/components/`. Name them `<Name>Component` (e.g., `CardComponent`). Each component gets a `.rb` file and `.html.erb` template in the same directory.
- **Lookbook previews** for every ViewComponent. Place previews in `test/components/previews/`. Name them `<Name>ComponentPreview`. Lookbook is available at `/lookbook` in development.
- **Hotwire** (Turbo + Stimulus) for interactivity — no heavy JS frameworks.

## Git

- **Small, focused commits.** One logical change per commit.
- **Commit message format:** imperative mood, lowercase after prefix. Prefixes: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.
- **Update docs in the same commit** if your change affects architecture, conventions, or deployment.
- **Feature branches, not worktrees.** Git worktrees don't play well with Rails (shared database, migration conflicts, tmp/log state). Use feature branches instead.

## Architecture patterns

- **Service objects for business logic.** Keep models thin (validations, associations, scopes) and extract multi-step operations into service objects in `app/services/`. Name them as nouns or verb phrases describing the operation (e.g. `HealthDataProcessor`, `WorkoutParser`). Controllers call services; services coordinate models.

## General principles

- **Follow tool conventions.** Use Rails generators, Devise helpers, Tailwind utilities as intended. If you're fighting a tool, stop — either it's the wrong tool or you have the wrong approach.
- **YAGNI.** Don't build for hypothetical future requirements.
- **DRY, but not prematurely.** Three similar lines are better than a premature abstraction.
