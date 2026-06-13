module Notion
  class RedFlagDetector
    RHR_DELTA_BPM = 5          # today's RHR this much above 7-day baseline
    HRV_DROP_RATIO = 0.8       # today's HRV below 80% of 7-day baseline
    SLEEP_MIN_HOURS = 6.5
    WEEKLY_WEIGHT_LOSS_KG = 1.0 # more than 1 kg lost vs 7 days ago

    def self.call(user, date:)
      new(user, date: date).call
    end

    def initialize(user, date:)
      @user = user
      @date = date
    end

    def call
      flags = []
      flags << "RHR up" if rhr_up?
      flags << "HRV down" if hrv_down?
      flags << "Sleep <6.5h" if sleep_short?
      flags << "Weight loss too fast" if weight_loss_too_fast?
      flags
    end

    private

    def day_value(name, date = @date)
      @user.health_metrics.where(metric_name: name, recorded_at: TrainingWeek.day_range(date))
        .order(recorded_at: :desc).first&.value&.to_f
    end

    def baseline(name)
      range = TrainingWeek.day_range(@date - 7).first..TrainingWeek.day_range(@date - 1).last
      values = @user.health_metrics.where(metric_name: name, recorded_at: range).pluck(:value)
      return nil if values.empty?
      values.sum.to_f / values.size
    end

    def rhr_up?
      today, base = day_value("resting_heart_rate"), baseline("resting_heart_rate")
      today && base && today >= base + RHR_DELTA_BPM
    end

    def hrv_down?
      today, base = day_value("heart_rate_variability"), baseline("heart_rate_variability")
      today && base && today <= base * HRV_DROP_RATIO
    end

    def sleep_short?
      sleep = day_value("sleep_analysis")
      sleep && sleep < SLEEP_MIN_HOURS
    end

    def weight_loss_too_fast?
      today = day_value("weight")
      week_ago = (1..3).lazy.map { |i| day_value("weight", @date - 7 - i + 1) }.find(&:itself) # nearest reading ~7 days back
      today && week_ago && (week_ago - today) > WEEKLY_WEIGHT_LOSS_KG
    end
  end
end
