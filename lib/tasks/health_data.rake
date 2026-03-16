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

  desc "Clear all health metrics and workouts, then reprocess all payloads"
  task reprocess_all: :environment do
    puts "Clearing #{HealthMetric.count} metrics and #{Workout.count} workouts..."
    HealthMetric.delete_all
    Workout.delete_all

    payloads = HealthPayload.order(:created_at)
    puts "Reprocessing #{payloads.count} payloads..."

    payloads.find_each do |payload|
      payload.update!(status: "pending")
      result = HealthDataProcessor.call(payload)
      if result.success
        puts "  ##{payload.id}: #{result.metrics_created} metrics, #{result.workouts_created} workouts"
      else
        puts "  ##{payload.id} FAILED: #{payload.reload.error_message}"
      end
    end

    puts "Done. #{HealthMetric.count} metrics, #{Workout.count} workouts."
  end
end
