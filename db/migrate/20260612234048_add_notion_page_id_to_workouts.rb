class AddNotionPageIdToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :notion_page_id, :string
    add_index :workouts, :notion_page_id
  end
end
