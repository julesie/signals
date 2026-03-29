class AddNotesToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :notes, :text
  end
end
