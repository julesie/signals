# Issue #2: Mobile-first design system: Tailwind v4 dark mode, PWA, ViewComponents, and styled views

**Issue:** [#2](https://github.com/julesie/signals/issues/2)
**Branch:** `issue-2-mobile-first-design-system`
**Status:** Done
**Created:** 2026-03-28

---

## Problem Summary

Signals is a personal health dashboard used primarily on iPhone. The app needs to feel native — installable from the home screen, dark mode by default, and mobile-first responsive. The current dashboard has functional Tailwind styling but no dark mode, no component system, and no established frontend conventions. Devise is installed but has no custom views. The PWA manifest exists but is commented out with incorrect theme colors (red). This issue establishes the design foundation so all future screens follow consistent patterns.

## Key Findings

### Current State
- **Tailwind v4.2.1** installed via `tailwindcss-rails` (v4.4.0), using Propshaft asset pipeline
- **No tailwind.config.js** — using defaults, which is fine since the issue explicitly says "use Tailwind defaults"
- **Tailwind CSS file** (`app/assets/tailwind/application.css`) contains only `@import "tailwindcss"` — dark mode setup goes here
- **Dashboard** (`app/views/dashboard/index.html.erb`) is the only app view — uses light-mode colors (bg-white, text-gray-900, etc.) and already has responsive grid breakpoints
- **Layout** (`app/views/layouts/application.html.erb`) has mobile meta tags, Devise flash messages, `container mx-auto mt-28 px-5` wrapper. PWA manifest link is commented out
- **PWA manifest** (`app/views/pwa/manifest.json.erb`) has `display: "standalone"`, red theme colors, references `/icon.png` (512x512) and `/icon.svg`
- **Devise** is configured with database_authenticatable, registerable, confirmable, rememberable, validatable. Routes exist (`devise_for :users`). No custom views generated
- **No ViewComponent or Lookbook** gems present
- **Test framework:** Minitest (not RSpec). Existing integration tests in `test/integration/` with Capybara/Selenium. Devise `sign_in` helper available
- **JS:** Importmaps + Stimulus. Only a hello_controller exists (unused)
- **No dark mode** classes anywhere in the codebase currently

### Icon Requirements for PWA
The user will supply the icon. Required formats:
- **512x512 PNG** — PWA install icon (maskable variant recommended)
- **192x192 PNG** — smaller PWA icon
- **180x180 PNG** — Apple touch icon
- **SVG** — scalable fallback
- **favicon.ico** — browser tab

### Tailwind v4 Dark Mode Approach
Tailwind v4 uses CSS-native dark mode via `@media (prefers-color-scheme: dark)` by default. The `dark:` variant works out of the box — no config needed. Since the user wants dark as default with Tailwind defaults, we use `dark:` prefixed classes throughout views and ensure the HTML has appropriate meta theme-color.

### ViewComponent + Lookbook
- `view_component` gem provides component architecture for Rails views
- `lookbook` gem provides a component preview UI (like Storybook)
- Both integrate with Minitest for component unit testing
- ViewComponent previews can live alongside Lookbook

## Proposed Approach

### 1. Infrastructure Setup
Add `view_component` and `lookbook` gems. Configure Lookbook for development. No Tailwind config file needed — v4 defaults are sufficient and the `dark:` variant works without configuration.

### 2. PWA Manifest & Theme
Enable the manifest link in the layout. Update theme/background colors from red to a dark neutral (e.g., Tailwind's zinc-900 `#18181b`). Update icon references. User supplies actual icon files.

### 3. Dark Mode Foundation
Force dark mode via `<html class="dark">` in the layout. Configure Tailwind v4 for class-based dark mode strategy in `application.css`. Set dark background/text defaults on body. All views use `dark:` variants.

### 4. Shared Layout Components
Extract reusable ViewComponents:
- **PageLayout** — standard page wrapper with consistent padding, max-width
- **Card** — content container with optional `flush` flag (removes padding for table-wrapper cases). Pipeline status bar stays as raw markup — different enough to not warrant the component.
- Create Lookbook previews for each

### 5. Devise Views
Generate Devise views (`rails generate devise:views`), then restyle core flows for dark mode, mobile-first: sign_in, sign_up, forgot_password, reset_password. Skip confirmation/unlock pages. All auth pages share a consistent layout: centered card on dark background, app name above the form.

### 6. Dashboard Restyling
- Convert all light-mode utilities to dark-mode equivalents
- Drop "Signals" `<h1>` heading from dashboard (nav bar handles branding), keep sync timestamp at top
- Workout table: stacked card layout on mobile, table on `md:` and up (6-column table is too cramped on iPhone)
- Maintain existing responsive grid breakpoints for metrics

### 7. Frontend Conventions Documentation
Update existing `docs/conventions.md` — add ViewComponent naming/structure, Lookbook usage, and "smoke tests only, no class assertions" guidance to the existing Frontend and Testing sections. One doc, one source of truth.

### 8. View Specs
Add smoke-level Minitest integration tests: login page renders, dashboard renders for authenticated user. No class/markup assertions — just assert response success and key content presence.

## Step-by-Step Tasks

- [ ] 1. Add `view_component` and `lookbook` gems to Gemfile, bundle install, configure Lookbook route in development
- [ ] 2. Configure Tailwind v4 dark mode — update `application.css` with dark defaults, set class-based dark mode strategy
- [ ] 3. Update PWA manifest — enable in layout, set dark theme colors, document icon requirements
- [ ] 4. Extract PageLayout ViewComponent with Lookbook preview
- [ ] 5. Extract Card ViewComponent with Lookbook preview
- [ ] 6. Generate and style Devise views (sign in, sign up, forgot password, reset password) — dark mode, mobile-first
- [ ] 7. Restyle application layout — dark background, update flash messages, add minimal nav bar (app name + sign out)
- [ ] 8. Restyle dashboard view — convert to dark mode, maintain responsive grid
- [ ] 9. Add smoke-level view specs for login and dashboard pages
- [ ] 10. Document frontend conventions (Tailwind patterns, ViewComponent usage, Lookbook, view testing)

## Open Questions / Unknowns

All resolved:
- **Dark mode:** Force dark via `<html class="dark">` — always dark, no toggle for now
- **Lookbook:** Dev-only gem group
- **Devise views:** Core flows only — sign in, sign up, password reset. Consistent auth layout (centered card, app name above)
- **Navigation:** Add minimal nav bar (app name + sign out) as part of this issue
- **Card component:** Single component with optional `flush` flag for table wrappers. Pipeline status bar stays as raw markup
- **Workout table:** Stacked cards on mobile, table on `md:+`
- **Dashboard heading:** Drop "Signals" h1 (nav bar covers branding), keep sync timestamp
- **Conventions:** Update existing `docs/conventions.md`, don't create a separate doc

---

*This plan is a living document — update it as understanding evolves.*
