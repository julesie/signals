class CreateNutritionProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :nutrition_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.integer :calorie_target, null: false, default: 1600
      t.integer :protein_target, null: false, default: 100
      t.timestamps
    end
  end
end
