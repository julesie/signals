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

    # 2. Fix CSV timestamps. The CSV import stored UTC times as local,
    #    so all timestamps are 8 hours early (PST offset). Shift them
    #    forward to correct local time. All CSV records are from the
    #    PST period (Feb-Mar before DST on Mar 8), except a few after
    #    Mar 8 which should use PDT (7 hours). But since DST changed
    #    Mar 8, we need to handle both offsets.
    #    Before Mar 8: add 8 hours (PST = UTC-8)
    #    Mar 8 onwards: add 7 hours (PDT = UTC-7)
    execute <<~SQL
      UPDATE workouts
      SET started_at = started_at + INTERVAL '8 hours',
          ended_at = ended_at + INTERVAL '8 hours'
      WHERE external_id LIKE 'csv-%'
      AND started_at < '2026-03-08'
    SQL

    execute <<~SQL
      UPDATE workouts
      SET started_at = started_at + INTERVAL '7 hours',
          ended_at = ended_at + INTERVAL '7 hours'
      WHERE external_id LIKE 'csv-%'
      AND started_at >= '2026-03-08'
    SQL

    # 3. Fix energy values on webhook records only.
    #    The previous fix migration (20260329023656) multiplied ALL
    #    pre-migration records by 4.184. For webhook records, this
    #    restored raw kJ values (they need dividing). For CSV-only
    #    records, it correctly restored kcal (leave them alone).
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned / 4.184, 1)
      WHERE energy_burned IS NOT NULL
      AND external_id NOT LIKE 'csv-%'
      AND created_at < '2026-03-28 22:24:06 UTC'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned * 4.184, 1)
      WHERE energy_burned IS NOT NULL
      AND external_id NOT LIKE 'csv-%'
      AND created_at < '2026-03-28 22:24:06 UTC'
    SQL

    raise ActiveRecord::IrreversibleMigration, "Cannot restore deleted CSV duplicate records"
  end
end
