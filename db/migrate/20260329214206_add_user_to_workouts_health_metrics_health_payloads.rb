class AddUserToWorkoutsHealthMetricsHealthPayloads < ActiveRecord::Migration[8.1]
  def up
    # Add nullable user_id columns
    add_reference :workouts, :user, null: true, foreign_key: true
    add_reference :health_metrics, :user, null: true, foreign_key: true
    add_reference :health_payloads, :user, null: true, foreign_key: true

    # Backfill all existing records to the single existing user
    user_id = User.find_by!(email: "jules@julescoleman.com").id
    Workout.update_all(user_id: user_id)
    HealthMetric.update_all(user_id: user_id)
    HealthPayload.update_all(user_id: user_id)

    # Make user_id NOT NULL now that all records are backfilled
    change_column_null :workouts, :user_id, false
    change_column_null :health_metrics, :user_id, false
    change_column_null :health_payloads, :user_id, false

    # Replace the old unique index on health_metrics with one scoped to user
    remove_index :health_metrics, [:metric_name, :recorded_at]
    add_index :health_metrics, [:user_id, :metric_name, :recorded_at], unique: true

    # Add composite index for common query patterns
    add_index :workouts, [:user_id, :started_at]
  end

  def down
    remove_index :workouts, [:user_id, :started_at]
    remove_index :health_metrics, [:user_id, :metric_name, :recorded_at]
    add_index :health_metrics, [:metric_name, :recorded_at], unique: true

    remove_reference :health_payloads, :user
    remove_reference :health_metrics, :user
    remove_reference :workouts, :user
  end
end
