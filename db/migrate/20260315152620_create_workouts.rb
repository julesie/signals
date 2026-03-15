class CreateWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :workouts do |t|
      t.string :external_id, null: false
      t.string :workout_type, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.integer :duration, null: false
      t.decimal :distance
      t.string :distance_units
      t.decimal :energy_burned
      t.jsonb :metadata

      t.timestamps

      t.index [:external_id], unique: true
    end
  end
end
