# Phase 1, Slice 1: Rails App Shell + Auth + Deploy — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Get a bare Rails 8 app running on Render behind Devise authentication with a placeholder dashboard.

**Architecture:** Standard Rails 8 app with Devise for single-user auth, Tailwind for styling, PostgreSQL for persistence. Deployed to Render via `render.yaml` blueprint.

**Tech Stack:** Ruby 3.3.10, Rails 8.1, PostgreSQL, Tailwind CSS, Devise, Render

---

### Task 0: Install Ruby 3.3.10 and Rails 8

**Step 1: Install Ruby 3.3.10 via rbenv**

Run: `rbenv install 3.3.10`

**Step 2: Set local Ruby version**

Run (from `/Users/jules/Code/signals`):
```bash
rbenv local 3.3.10
ruby --version
```
Expected: `ruby 3.3.10`

**Step 3: Install Rails 8**

Run: `gem install rails`

**Step 4: Verify**

Run: `rails --version`
Expected: `Rails 8.x.x`

---

### Task 1: Generate Rails app

**Files:**
- Create: Full Rails app structure in `/Users/jules/Code/signals`

**Step 1: Back up PROJECT.md**

Run:
```bash
cp /Users/jules/Code/signals/PROJECT.md /tmp/PROJECT.md
```

**Step 2: Generate Rails app into a temp directory**

Run:
```bash
cd /tmp
rails new signals --database=postgresql --css=tailwind --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-action-cable --skip-jbuilder
```

**Step 3: Copy generated files into the project directory**

Run:
```bash
cp -r /tmp/signals/* /Users/jules/Code/signals/
cp /tmp/signals/.* /Users/jules/Code/signals/ 2>/dev/null || true
```

Note: This preserves the existing `.git` directory since `cp` won't overwrite directories.

**Step 4: Restore PROJECT.md into docs/**

Run:
```bash
mkdir -p /Users/jules/Code/signals/docs
cp /tmp/PROJECT.md /Users/jules/Code/signals/docs/PROJECT.md
```

**Step 5: Verify the app structure**

Run:
```bash
cd /Users/jules/Code/signals
ls app config db Gemfile
```
Expected: All four listed without error.

**Step 6: Install dependencies**

Run:
```bash
cd /Users/jules/Code/signals
bundle install
```

**Step 7: Create the database**

Run:
```bash
cd /Users/jules/Code/signals
bin/rails db:create
```

**Step 8: Verify Rails boots and default tests pass**

Run:
```bash
cd /Users/jules/Code/signals
bin/rails test
```
Expected: `0 runs, 0 failures` (no tests yet, but Rails boots)

**Step 9: Commit**

```bash
git add -A
git commit -m "feat: generate Rails 8 app with PostgreSQL and Tailwind"
```

---

### Task 2: Add Devise and generate User model

**Files:**
- Modify: `Gemfile`
- Create: `app/models/user.rb`
- Create: `db/migrate/*_devise_create_users.rb`
- Create: `config/initializers/devise.rb`
- Create: `config/locales/devise.en.yml`

**Step 1: Add Devise to Gemfile**

Add to `Gemfile`:
```ruby
gem "devise"
```

**Step 2: Install**

Run:
```bash
cd /Users/jules/Code/signals
bundle install
```

**Step 3: Run Devise generators**

Run:
```bash
bin/rails generate devise:install
bin/rails generate devise User
```

**Step 4: Migrate**

Run:
```bash
bin/rails db:migrate
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Devise with User model"
```

---

### Task 3: Configure Devise and lock down the app

**Files:**
- Modify: `app/models/user.rb` — remove `:registerable`
- Modify: `app/controllers/application_controller.rb` — add `before_action :authenticate_user!`
- Modify: `config/initializers/devise.rb` — set `config.sign_out_via = :get` (simpler for single-user app)

**Step 1: Disable registration in User model**

In `app/models/user.rb`, remove `:registerable` from the `devise` call so the line reads something like:

```ruby
devise :database_authenticatable,
       :recoverable, :rememberable, :validatable
```

**Step 2: Add authentication requirement to ApplicationController**

In `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
end
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: lock down app with Devise, disable registration"
```

---

### Task 4: Create seed file

**Files:**
- Modify: `db/seeds.rb`

**Step 1: Write idempotent seed**

Replace contents of `db/seeds.rb` with:

```ruby
User.find_or_create_by!(email: "jules@julescoleman.com") do |user|
  user.password = "changeme123!"
end
```

**Step 2: Run seed**

Run:
```bash
cd /Users/jules/Code/signals
bin/rails db:seed
```

**Step 3: Verify in console**

Run:
```bash
bin/rails runner "puts User.count"
```
Expected: `1`

**Step 4: Run seed again to verify idempotency**

Run:
```bash
bin/rails db:seed
bin/rails runner "puts User.count"
```
Expected: Still `1`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add seed for default user account"
```

---

### Task 5: Write integration test for authentication

**Files:**
- Create: `test/integration/authentication_test.rb`

**Step 1: Write the test**

Create `test/integration/authentication_test.rb`:

```ruby
require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "unauthenticated user is redirected to sign in" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "authenticated user can access root" do
    user = User.create!(email: "test@example.com", password: "password123!")
    sign_in user
    get root_path
    assert_response :success
  end
end
```

Note: This test will fail until the DashboardController exists (Task 6). That's expected — write it first, then make it pass.

**Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/jules/Code/signals
bin/rails test test/integration/authentication_test.rb
```
Expected: FAIL — `root_path` is not defined yet.

**Step 3: Commit the failing test**

```bash
git add -A
git commit -m "test: add integration tests for authentication flow"
```

---

### Task 6: Create DashboardController and root route

**Files:**
- Create: `app/controllers/dashboard_controller.rb`
- Create: `app/views/dashboard/index.html.erb`
- Modify: `config/routes.rb`

**Step 1: Add Devise test helpers**

Check `test/test_helper.rb` includes Devise test helpers. Add if not present:

```ruby
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
```

**Step 2: Create the controller**

Create `app/controllers/dashboard_controller.rb`:

```ruby
class DashboardController < ApplicationController
  def index
  end
end
```

**Step 3: Create the view**

Create `app/views/dashboard/index.html.erb`:

```erb
<div class="min-h-screen flex items-center justify-center">
  <div class="text-center">
    <h1 class="text-4xl font-bold text-gray-900">Signals</h1>
    <p class="mt-2 text-gray-600">Welcome, <%= current_user.email %></p>
  </div>
</div>
```

**Step 4: Add root route**

In `config/routes.rb`, add inside the `Rails.application.routes.draw` block:

```ruby
devise_for :users
root "dashboard#index"
```

Note: `devise_for :users` may already be present from the Devise generator.

**Step 5: Run authentication tests — they should now pass**

Run:
```bash
cd /Users/jules/Code/signals
bin/rails test test/integration/authentication_test.rb
```
Expected: 2 runs, 0 failures

**Step 6: Verify manually in browser**

Run:
```bash
bin/rails server
```
Visit `http://localhost:3000` — should redirect to sign-in. Log in with `jules@julescoleman.com` / `changeme123!` — should see the Signals dashboard.

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: add dashboard controller as root with Tailwind styling"
```

---

### Task 7: Create render.yaml

**Files:**
- Create: `render.yaml`
- Create: `bin/render-build.sh`

**Step 1: Create the build script**

Create `bin/render-build.sh`:

```bash
#!/usr/bin/env bash
set -o errexit

bundle install
bundle exec rails assets:precompile
bundle exec rails db:migrate
bundle exec rails db:seed
```

**Step 2: Make it executable**

Run: `chmod +x bin/render-build.sh`

**Step 3: Create render.yaml**

Create `render.yaml` in the project root:

```yaml
databases:
  - name: signals-db
    plan: free
    databaseName: signals
    user: signals

services:
  - type: web
    name: signals
    runtime: ruby
    plan: free
    buildCommand: "./bin/render-build.sh"
    startCommand: "bundle exec puma -C config/puma.rb"
    envVars:
      - key: DATABASE_URL
        fromDatabase:
          name: signals-db
          property: connectionURI
      - key: RAILS_MASTER_KEY
        sync: false
      - key: RAILS_ENV
        value: production
      - key: RAILS_LOG_TO_STDOUT
        value: "true"
```

Note: `RAILS_MASTER_KEY` is set to `sync: false` meaning you'll paste it manually in the Render dashboard after first deploy.

**Step 4: Verify render.yaml syntax**

Run:
```bash
ruby -ryaml -e "YAML.safe_load_file('render.yaml'); puts 'Valid YAML'"
```
Expected: `Valid YAML`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add render.yaml blueprint for Render deployment"
```

---

### Task 8: Final verification and deploy prep

**Step 1: Run full test suite**

Run:
```bash
cd /Users/jules/Code/signals
bin/rails test
```
Expected: All tests pass.

**Step 2: Verify production asset compilation**

Run:
```bash
RAILS_ENV=production SECRET_KEY_BASE=dummy bin/rails assets:precompile
```
Expected: Completes without error.

**Step 3: Clean up precompiled assets**

Run:
```bash
bin/rails assets:clobber
```

**Step 4: Note the master key for Render**

Run:
```bash
cat config/master.key
```
Save this value — you'll paste it as `RAILS_MASTER_KEY` in the Render dashboard.

**Step 5: Push to GitHub and deploy**

```bash
git remote add origin <github-repo-url>
git push -u origin main
```

Then in Render dashboard: New > Blueprint > select the repo > deploy.

**Step 6: After deploy, verify**

Visit the Render URL — should see the Devise sign-in page. Log in with `jules@julescoleman.com` / `changeme123!`.
