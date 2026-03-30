namespace :metrics do
  desc "Backfill weight and body fat metrics from Health Auto Export CSVs"
  task backfill: :environment do
    require "csv"

    if ENV["PRODUCTION"] == "true"
      render_url = ENV["RENDER_DATABASE_URL"] || begin
        env_file = Rails.root.join(".env")
        env_file.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")
          k, v = line.split("=", 2)
          break v.delete_prefix('"').delete_suffix('"') if k.strip == "RENDER_DATABASE_URL"
        end
      end
      abort "Set RENDER_DATABASE_URL in .env or environment" if render_url.blank?
      ActiveRecord::Base.establish_connection(render_url)
      puts "Connected to production database"
    end

    user = User.find_by!(email: "jules@julescoleman.com")

    files = {
      "weight" => {path: Rails.root.join("tmp/weight_backfill.csv"), units: "kg", value_column: 1},
      "body_fat_percentage" => {path: Rails.root.join("tmp/body_fat_backfill.csv"), units: "%", value_column: 1}
    }

    files.each do |metric_name, config|
      unless File.exist?(config[:path])
        puts "Skipping #{metric_name} — #{config[:path]} not found"
        next
      end

      created = 0
      updated = 0

      CSV.foreach(config[:path], headers: true) do |row|
        recorded_at = Time.parse(row[0])
        value = row[config[:value_column]].to_f
        source = row[2]

        existing = user.health_metrics.find_by(metric_name: metric_name, recorded_at: recorded_at)
        if existing
          existing.update!(value: value, units: config[:units], metadata: {"source" => source})
          updated += 1
        else
          user.health_metrics.create!(
            metric_name: metric_name,
            recorded_at: recorded_at,
            value: value,
            units: config[:units],
            metadata: {"source" => source}
          )
          created += 1
        end
      end

      puts "#{metric_name}: #{created} created, #{updated} updated"
    end
  end
end
