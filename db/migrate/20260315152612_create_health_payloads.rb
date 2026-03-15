class CreateHealthPayloads < ActiveRecord::Migration[8.1]
  def change
    create_table :health_payloads do |t|
      t.jsonb :raw_json, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end
  end
end
