# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_29_003111) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "health_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata"
    t.string "metric_name", null: false
    t.datetime "recorded_at", null: false
    t.string "units", null: false
    t.datetime "updated_at", null: false
    t.decimal "value", null: false
    t.index ["metric_name", "recorded_at"], name: "index_health_metrics_on_metric_name_and_recorded_at", unique: true
  end

  create_table "health_payloads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.jsonb "raw_json", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
  end

  create_table "plans", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.text "daily_suggestion"
    t.datetime "suggestion_generated_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_plans_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "distance"
    t.string "distance_units"
    t.integer "duration", null: false
    t.datetime "ended_at", null: false
    t.decimal "energy_burned"
    t.string "external_id", null: false
    t.jsonb "metadata"
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.string "workout_type", null: false
    t.index ["external_id"], name: "index_workouts_on_external_id", unique: true
  end

  add_foreign_key "plans", "users"
end
