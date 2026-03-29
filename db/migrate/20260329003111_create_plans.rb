class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.text :content
      t.text :daily_suggestion
      t.datetime :suggestion_generated_at

      t.timestamps
    end
  end
end
