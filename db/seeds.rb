user = User.find_or_create_by!(email: "jules@julescoleman.com") do |user|
  user.password = "changeme123!"
end

user.create_plan unless user.plan

# Import historical health data from CSV (idempotent — upserts on re-run)
metrics_csv = Rails.root.join("db/seed_data/HealthAutoExport-2026-02-13-2026-03-15.csv")
workouts_csv = Rails.root.join("db/seed_data/Workouts-20260213_000000-20260315_235959.csv")

if metrics_csv.exist?
  puts "Importing historical health data..."
  result = CsvImporter.call(
    metrics_csv_path: metrics_csv.to_s,
    workouts_csv_path: workouts_csv.exist? ? workouts_csv.to_s : nil
  )
  puts "  Metrics: #{result.metrics_created} created, #{result.metrics_updated} updated"
  puts "  Workouts: #{result.workouts_created} created, #{result.workouts_updated} updated"
end
