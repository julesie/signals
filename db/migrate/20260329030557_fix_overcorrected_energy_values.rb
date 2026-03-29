class FixOvercorrectedEnergyValues < ActiveRecord::Migration[8.1]
  def up
    # 1. Delete remaining CSV duplicates. The previous migration matched on
    #    date, but CSV times are UTC while webhook times include the Pacific
    #    offset (7 hours later), so they land on different dates.
    #    Match on type + duration instead, which is unique enough.
    execute <<~SQL
      DELETE FROM workouts
      WHERE external_id LIKE 'csv-%'
      AND id IN (
        SELECT csv.id
        FROM workouts csv
        JOIN workouts webhook ON csv.workout_type = webhook.workout_type
          AND csv.duration = webhook.duration
          AND webhook.external_id NOT LIKE 'csv-%'
        WHERE csv.external_id LIKE 'csv-%'
      )
    SQL

    # 2. Fix energy values on remaining pre-migration records.
    #    Previous fix migration multiplied by 4.184, restoring raw kJ
    #    instead of the correct kcal. Divide by 4.184 to get kcal.
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned / 4.184, 1)
      WHERE energy_burned IS NOT NULL
      AND created_at < '2026-03-28 22:24:06 UTC'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned * 4.184, 1)
      WHERE energy_burned IS NOT NULL
      AND created_at < '2026-03-28 22:24:06 UTC'
    SQL

    raise ActiveRecord::IrreversibleMigration, "Cannot restore deleted CSV duplicate records"
  end
end
