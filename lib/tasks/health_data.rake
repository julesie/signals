namespace :health_data do
  desc "Reprocess all pending/failed health payloads, or a specific one by ID"
  task reprocess: :environment do
    payloads = if ENV["PAYLOAD_ID"]
      HealthPayload.where(id: ENV["PAYLOAD_ID"])
    else
      HealthPayload.where(status: %w[pending failed])
    end

    if payloads.empty?
      puts "No payloads to reprocess. Use PAYLOAD_ID=1 to force a specific one."
      next
    end

    payloads.find_each do |payload|
      puts "Reprocessing payload ##{payload.id} (status: #{payload.status})..."
      payload.update!(status: "pending")
      result = HealthDataProcessor.call(payload)
      if result.success
        puts "  OK: #{result.metrics_created} metrics, #{result.workouts_created} workouts"
      else
        puts "  FAILED: #{payload.reload.error_message}"
      end
    end
  end

  desc "Rebuild all health data from stored payloads (deduplicates overlapping data)"
  task rebuild: :environment do
    puts "Merging #{HealthPayload.count} payloads and rebuilding..."

    results = HealthDataReprocessor.call
    m = results[:metrics]
    w = results[:workouts]

    puts "Done. Created #{m.created} metrics, #{w.created} workouts."
    puts "Total: #{HealthMetric.count} metrics, #{Workout.count} workouts."
  end
end
