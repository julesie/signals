namespace :health_data do
  desc "Reprocess a specific payload by ID"
  task reprocess: :environment do
    payload_id = ENV.fetch("PAYLOAD_ID") { abort "Usage: bin/rails health_data:reprocess PAYLOAD_ID=1" }
    payload = HealthPayload.find(payload_id)

    puts "Reprocessing payload ##{payload.id} (status: #{payload.status})..."
    payload.update!(status: "pending")
    result = HealthDataProcessor.call(payload)
    if result.success
      puts "  OK: #{result.metrics_created} created, #{result.metrics_updated} updated, #{result.workouts_created} workouts"
    else
      puts "  FAILED: #{payload.reload.error_message}"
    end
  end

  desc "Rebuild all health data from stored payloads (deduplicates overlapping data)"
  task rebuild: :environment do
    puts "Merging #{HealthPayload.count} payloads and rebuilding..."

    results = HealthDataReprocessor.call
    m = results[:metrics]
    w = results[:workouts]

    puts "Done. Created #{m.created} metrics (#{m.updated} updated), #{w.created} workouts."
    puts "Total: #{HealthMetric.count} metrics, #{Workout.count} workouts."
  end

  desc "Nuke all health data (payloads, metrics, workouts)"
  task nuke: :environment do
    puts "Deleting #{HealthPayload.count} payloads, #{HealthMetric.count} metrics, #{Workout.count} workouts..."
    HealthMetric.delete_all
    Workout.delete_all
    HealthPayload.delete_all
    puts "Clean slate."
  end
end
