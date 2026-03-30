class CreateFoods < ActiveRecord::Migration[8.1]
  def change
    create_table :foods do |t|
      t.references :user, null: false, foreign_key: true
      t.text :description, null: false
      t.decimal :kcal, null: false
      t.decimal :protein, precision: 5, scale: 1
      t.decimal :carbs, precision: 5, scale: 1
      t.decimal :fat, precision: 5, scale: 1
      t.decimal :fibre, precision: 5, scale: 1
      t.decimal :alcohol, precision: 5, scale: 1, default: 0
      t.timestamps
    end
  end
end
