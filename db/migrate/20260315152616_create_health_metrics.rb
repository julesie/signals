class CreateHealthMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :health_metrics do |t|
      t.string :metric_name, null: false
      t.datetime :recorded_at, null: false
      t.decimal :value, null: false
      t.string :units, null: false
      t.jsonb :metadata

      t.timestamps

      t.index [:metric_name, :recorded_at], unique: true
    end
  end
end
