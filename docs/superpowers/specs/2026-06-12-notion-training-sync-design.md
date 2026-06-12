# Notion Training Sync — Design

Date: 2026-06-12
Status: Approved by Jules (sections 1–3 approved in brainstorming session)

## Context

Jules is training for the SF Half Marathon (race day: 2026-07-26) using a Runna
plan, with Claude iOS as a daily coach. Three Notion databases under the
"SF Half Marathon 2026" page track training:

- **Daily Logs** (data source `78d04a40-94e2-49e7-9199-7647f9f185bb`) — one row
  per day: weight, sleep, HRV, RHR, calories, macros, mood, red flags, notes.
  Titles like `Thu Jun 11 (W6 D4) - Rest`.
- **Workouts** (data source `ffb81591-e4b5-4204-bd12-45d939757458`) — **plan-first**:
  the full Runna plan is pre-seeded as rows with `Status: Planned`, titles like
  `W1 Fri - 5km Easy Run`. Completed sessions get actuals filled in and
  `Status: Done`.
- **Weekly Reviews** (data source `a36524f3-9afd-4cf9-8be1-d0bf0b2c21fb`) — one
  row per training week: aggregates plus narrative (What Worked / What Broke /
  Adjustment for Next Week / Status).

Today Claude iOS manually extracts Apple Health data and updates these — slow
and manual. Signals already receives Apple Health data automatically via
webhook (`POST /api/v1/health_data` → `HealthDataProcessor` →
`health_metrics` + `workouts` tables) and runs Solid Queue (in Puma, on
Render) with recurring tasks in `config/recurring.yml`. Signals also already
makes LLM calls via the `ruby_llm` gem (`PlanSuggestionGenerator`,
`PlanAdherenceGenerator` patterns), and stores the Runna plan in
`plans.content`.

## Goal

Keep all three Notion databases up to date automatically — data fields fresh
throughout the day, LLM commentary after workouts and at end of day, weekly
review on Sunday evenings — with no dependency on Claude iOS sessions, the
laptop, or MCP. Claude iOS chats remain purely conversational. Runs until at
least race day with no babysitting.

## Decisions made

- **Lives in Signals** (Rails), not Claude Code / scheduled agents. Zero new
  infrastructure; runs server-side 24/7.
- **No MCP server** for the sync. Signals talks to the Notion REST API
  directly with an internal integration token. (An MCP read interface for
  Claude iOS chats is a possible later enhancement, out of scope here.)
- **Full automation** including LLM commentary (not data-only).
- **Commentary cadence:** workout commentary once when a workout first syncs;
  daily log commentary in a ~10pm pass; weekly review Sunday ~9pm.
- **Daily commentary destination:** the `Notes` property of the Daily Logs row
  (page body untouched). Workout `Notes` remains human-owned.
- **Alcohol:** convert grams → drinks as `alcohol_g / 14`, rounded to nearest
  0.5.
- **Red Flags (daily):** automation auto-sets only the data-computable flags
  (`RHR up`, `HRV down`, `Sleep <6.5h`, `Weight loss too fast`) against a
  7-day baseline, **merge-only** — it never removes flags a human set.

## Architecture

```
Apple Health export (phone)
        │  POST /api/v1/health_data            (existing)
        ▼
HealthDataProcessor                             (existing)
        │  on success, enqueues ───────────────► NotionSyncJob        (new)
        ▼                                            │
health_metrics / workouts tables                     ▼
                                               Notion::Client (new) ──► Notion REST API

config/recurring.yml additions:
  notion_catchup        — every 30 min: re-sync rolling window (safety net)
  daily_log_commentary  — daily ~10pm PT: LLM narrative → Daily Logs Notes
  weekly_review         — Sunday ~9pm PT: create + fill Weekly Reviews row
```

### Components (all new, in Signals)

| Component | Responsibility |
|---|---|
| `Notion::Client` (`app/services/notion/client.rb`) | Minimal Notion REST wrapper: `query_data_source`, `create_page`, `update_page`. `Net::HTTP`, no new gem. Auth via `NOTION_API_TOKEN`. |
| `Notion::DailyLogSync` | Upsert daily log row for a date (find by `Date` property, create with generated title if missing); write data fields only. |
| `Notion::WorkoutSync` | Match an Apple Health workout to a `Planned` Notion row (by PT date + type); fill actuals, set `Status: Done`; create row if unmatched; persist `notion_page_id` on the `workouts` record. Chains `WorkoutCommentaryJob` on first sync. |
| `NotionSyncJob` (Solid Queue) | Orchestrates DailyLogSync + WorkoutSync for the rolling window. Enqueued by webhook success and by `notion_catchup`. |
| `Notion::WorkoutCommentaryGenerator` + `WorkoutCommentaryJob` | One `RubyLLM.chat` call (PlanSuggestionGenerator pattern); context: the workout, plan content, recent training. Writes commentary. Runs once per workout. |
| `Notion::DailyLogCommentaryGenerator` + job | ~10pm PT: builds full-day context (metrics, food, workouts, plan), writes narrative to the row's `Notes`; computes + merges data-computable Red Flags. |
| `Notion::WeeklyReviewGenerator` + job | Sunday ~9pm PT: computes aggregates from DB, sums `Planned km` from that week's planned Notion rows, LLM writes Status / What Worked / What Broke / Adjustment / Red Flags Triggered. |

## Field mapping & ownership

Rule: **every Notion property has exactly one owner — automation or human.
The sync never includes human-owned properties in any write payload.** This
makes all re-syncs safe.

### Daily Logs (upsert by `Date`)

| Property | Owner | Source |
|---|---|---|
| Day (title) | automation (on create only) | `Thu Jun 12 (W6 D5) - <Day Type>`; week/day numbering derived from `TRAINING_WEEK1_START` |
| Date | automation | PT date |
| Weight (kg), Sleep Hours, HRV, RHR | automation | `health_metrics` (latest value for the date; sleep summed if needed) |
| Calories Burned | automation | `health_metrics` (active + basal energy for the date) |
| Calories Actual, Protein (g), Fat (g), Carbs (g) | automation | `food_logs` daily totals |
| Alcohol (drinks) | automation | `food_logs` alcohol grams ÷ 14, rounded to 0.5 |
| Calories Target | automation | `nutrition_profiles.calorie_target` |
| Deficit | automation | computed: Calories Actual − Calories Burned |
| Day Type | automation | from matched workout type(s); `Rest` if none |
| Notes | automation (commentary) | end-of-day LLM narrative |
| Red Flags | shared, merge-only | automation adds `RHR up`, `HRV down`, `Sleep <6.5h`, `Weight loss too fast` when thresholds trip vs 7-day baseline; never removes |
| Mood, Sleep Score, Withdrawal Bleed | human | never touched |

### Workouts (match-and-fill)

Matching: Apple Health workout → `Planned`/`Modified` Notion row with same PT
date and compatible type. Matched `notion_page_id` stored on `workouts` row;
subsequent syncs use the stored ID. Unmatched workouts (golf, unplanned
strength, etc.) create a new row with `Status: Done`.

| Property | Owner | Source |
|---|---|---|
| Actual Distance (km) | automation | `workouts.distance` (converted to km) |
| Actual Duration (min) | automation | `workouts.duration` / 60 |
| Actual Avg HR | automation | `workouts.metadata` avg HR if present |
| Actual Avg Pace | automation | computed `duration / distance`, formatted mm:ss/km |
| kCal Burned | automation | `workouts.energy_burned` |
| Status | automation | → `Done` on match/create (never overwrites `Skipped`) |
| Date, Session (title), Type, Week, Planned * | human/pre-seeded | set on create for unmatched workouts only |
| Felt, RPE, Fueled Properly, Hit Prescribed Pace, Notes | human | never touched |

Workout commentary (LLM, once per workout): appended to the workout page
body — `Notes` is human-owned here.

### Weekly Reviews (created Sunday evening)

| Property | Owner | Source |
|---|---|---|
| Week (title), Week Number, Week Start | automation | from `TRAINING_WEEK1_START` |
| Actual km, Long Run Distance (km) | automation | `workouts` aggregates for the week |
| Planned km | automation | summed from that week's planned Notion workout rows |
| Quality Session Done, Strength Done | automation | from week's workouts |
| Avg HRV, Avg RHR, Avg Sleep Hours | automation | `health_metrics` weekly averages |
| Weight Start (kg), Weight End (kg) | automation | first/last weight of the week |
| Status, What Worked, What Broke, Adjustment for Next Week, Red Flags Triggered | automation (LLM) | weekly review generator |

## Plumbing

- **Migration:** add `notion_page_id` (string, nullable, indexed) to `workouts`.
- **Env vars (Render):** `NOTION_API_TOKEN`, `NOTION_DAILY_LOGS_DS_ID`,
  `NOTION_WORKOUTS_DS_ID`, `NOTION_WEEKLY_REVIEWS_DS_ID`,
  `TRAINING_WEEK1_START`.
- **Notion auth setup (manual, one-time):** create an internal integration at
  notion.so/my-integrations; share the three databases with it; put its token
  in Render.
- **Timezone:** all date bucketing in `America/Los_Angeles`.
- **Rolling window:** sync touches today + yesterday (PT) only — historical
  pages never churn.
- Daily/weekly page lookup is a Notion data-source query by date property —
  no local lookup table (single-user volume).

## Error handling

- Services follow the existing pattern: rescue, `Rails.logger.error`, return
  `Result` struct. Solid Queue retries transient failures; persistent ones are
  visible in `solid_queue_failed_executions`.
- All writes idempotent (upsert by date / `notion_page_id`; merge-only
  multi-selects), so retries and the 30-min catch-up are always safe.
- Commentary jobs are independent of data sync jobs — LLM failure cannot block
  data freshness.
- Notion rate limits (~3 req/s) are far above this workload; no throttling
  logic needed.

## Testing

- Minitest unit tests with a stubbed `Notion::Client`:
  - grams→drinks conversion and rounding
  - planned-row matching by date + type (incl. no-match → create)
  - merge-only Red Flags behavior
  - week/day numbering from `TRAINING_WEEK1_START`
  - human-owned properties never appear in write payloads
- Manual end-to-end before enabling schedules: one-shot `rails runner` sync of
  a single day against the real databases, verified by eye in Notion.

## Rollout

1. Ship with recurring tasks commented out.
2. Run one-shot sync; verify in Notion.
3. Enable `notion_catchup` (30-min).
4. After a clean day, enable webhook-chained `NotionSyncJob` and the evening
   commentary + weekly review tasks.
5. Post-race: delete the recurring entries (or keep for the next race).

## Out of scope

- MCP server / read API for Claude iOS chats (possible follow-up).
- Multi-user support — hardcoded to the single user, per project convention.
- Backfilling historical Notion pages.
