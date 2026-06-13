module Notion
  class TrainingWeek
    TIME_ZONE = "America/Los_Angeles"

    def self.today
      Time.now.in_time_zone(TIME_ZONE).to_date
    end

    def self.day_range(date)
      tz = ActiveSupport::TimeZone[TIME_ZONE]
      tz.local(date.year, date.month, date.day).all_day
    end

    def initialize(date, week1_start: Date.parse(ENV.fetch("TRAINING_WEEK1_START")))
      @date = date
      @week1_start = week1_start
    end

    attr_reader :date

    def week_number = ((@date - @week1_start).to_i / 7) + 1

    def day_number = ((@date - @week1_start).to_i % 7) + 1

    def week_start = @week1_start + ((week_number - 1) * 7)

    def label = "W#{week_number} D#{day_number}"

    def daily_title(day_type)
      "#{@date.strftime("%a %b %-d")} (#{label}) - #{day_type}"
    end
  end
end
