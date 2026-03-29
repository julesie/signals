class AddAdherenceFieldsToPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :plans, :adherence_summary, :text
    add_column :plans, :adherence_summary_generated_at, :datetime
  end
end
