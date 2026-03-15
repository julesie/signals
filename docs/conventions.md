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
- **Minimal view-level tests.** Don't test markup unless it encodes important logic.
- **Every test should have clear value.** Prefer a smaller, smarter test suite over comprehensive-but-redundant coverage. If a test doesn't catch a meaningful failure, delete it.
- **No excessive mocking.** Test real behavior wherever practical.
- Run tests: `bin/rails test`

## Frontend

- **Tailwind CSS only.** No custom CSS unless absolutely unavoidable.
- **Extract components** (partials, ViewComponents, or helpers) whenever HTML patterns repeat. Avoid copy-pasting complex markup.
- **Hotwire** (Turbo + Stimulus) for interactivity — no heavy JS frameworks.

## Git

- **Small, focused commits.** One logical change per commit.
- **Commit message format:** imperative mood, lowercase after prefix. Prefixes: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.
- **Update docs in the same commit** if your change affects architecture, conventions, or deployment.

## General principles

- **Follow tool conventions.** Use Rails generators, Devise helpers, Tailwind utilities as intended. If you're fighting a tool, stop — either it's the wrong tool or you have the wrong approach.
- **YAGNI.** Don't build for hypothetical future requirements.
- **DRY, but not prematurely.** Three similar lines are better than a premature abstraction.
