class AddEstimatedToFoodLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :food_logs, :estimated, :boolean, default: true, null: false
  end
end
