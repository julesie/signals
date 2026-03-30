class CreateFoodLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :food_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :food, null: false, foreign_key: true
      t.datetime :consumed_at, null: false
      t.string :mealtime
      t.decimal :kcal
      t.decimal :protein, precision: 5, scale: 1
      t.decimal :carbs, precision: 5, scale: 1
      t.decimal :fat, precision: 5, scale: 1
      t.decimal :fibre, precision: 5, scale: 1
      t.decimal :alcohol, precision: 5, scale: 1
      t.timestamps
    end

    add_index :food_logs, [:user_id, :consumed_at]
  end
end
