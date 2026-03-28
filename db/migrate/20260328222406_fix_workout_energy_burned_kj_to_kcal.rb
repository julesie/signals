class FixWorkoutEnergyBurnedKjToKcal < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned / 4.184, 1)
      WHERE energy_burned IS NOT NULL
    SQL
  end

  def down
    execute <<~SQL
      UPDATE workouts
      SET energy_burned = ROUND(energy_burned * 4.184, 1)
      WHERE energy_burned IS NOT NULL
    SQL
  end
end
