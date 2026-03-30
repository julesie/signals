class WorkoutParser
  Result = Struct.new(:created, :skipped, keyword_init: true)

  COMMON_FIELDS = %w[id name start end duration location isIndoor].freeze
  KJ_TO_KCAL = 4.184

  def self.call(workouts_data, user:)
    new(workouts_data, user: user).call
  end

  def initialize(workouts_data, user:)
    @workouts_data = workouts_data
    @user = user
  end

  def call
    created = 0
    skipped = 0

    @workouts_data.each do |workout_data|
      external_id = workout_data["id"]

      if @user.workouts.exists?(external_id: external_id)
        skipped += 1
      else
        @user.workouts.create!(
          external_id: external_id,
          workout_type: workout_data["name"],
          started_at: Time.parse(workout_data["start"]),
          ended_at: Time.parse(workout_data["end"]),
          duration: workout_data["duration"],
          distance: workout_data.dig("distance", "qty"),
          distance_units: workout_data.dig("distance", "units"),
          energy_burned: convert_energy(workout_data["activeEnergyBurned"]),
          metadata: build_metadata(workout_data)
        )
        created += 1
      end
    end

    Result.new(created: created, skipped: skipped)
  end

  private

  def convert_energy(energy)
    return nil unless energy
    qty = energy["qty"]
    return nil unless qty
    (energy["units"] == "kJ") ? (qty / KJ_TO_KCAL).round(1) : qty
  end

  def build_metadata(workout_data)
    metadata = workout_data.except(*COMMON_FIELDS)

    # Remove fields already stored as columns
    metadata.delete("distance")
    metadata.delete("activeEnergyBurned")

    # Normalize heart rate summary from nested {qty, units} to flat values
    if (hr = metadata.delete("heartRate"))
      metadata["heartRate"] = {
        "min" => hr.dig("min", "qty"),
        "avg" => hr.dig("avg", "qty"),
        "max" => hr.dig("max", "qty")
      }
    end

    metadata
  end
end
