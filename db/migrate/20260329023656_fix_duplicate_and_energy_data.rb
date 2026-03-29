class FixDuplicateAndEnergyData < ActiveRecord::Migration[8.1]
  def up
    # 1. Delete CSV-imported duplicates that have webhook equivalents
    #    (same workout_type, same duration, same date)
    execute <<~SQL
      DELETE FROM workouts
      WHERE external_id LIKE 'csv-%'
      AND id IN (
        SELECT csv.id
        FROM workouts csv
        JOIN workouts webhook ON csv.workout_type = webhook.workout_type
          AND csv.duration = webhook.duration
          AND csv.started_at::date = webhook.started_at::date
          AND webhook.external_id NOT LIKE 'csv-%'
        WHERE csv.external_id LIKE 'csv-%'
      )
    SQL

    # 2. Reverse the incorrect kJ-to-kcal conversion on pre-migration records.
    #    Migration 20260328222406 divided ALL energy_burned by 4.184, but
    #    values were already in kcal (CSV imports were kcal, and WorkoutParser
    #    converts kJ→kcal before storing). Only records created before that
    #    migration need reversal. Records created after are correct.
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned * 4.184, 1)
      WHERE energy_burned IS NOT NULL
      AND created_at < '2026-03-28 22:24:06 UTC'
    SQL
  end

  def down
    # Re-apply the division for pre-migration records
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned / 4.184, 1)
      WHERE energy_burned IS NOT NULL
      AND created_at < '2026-03-28 22:24:06 UTC'
    SQL

    # Cannot restore deleted CSV records
    raise ActiveRecord::IrreversibleMigration, "Cannot restore deleted CSV duplicate records"
  end
end
