class HolidayImport

  include ActiveModel::Validations

  attr_accessor :holidays,
    :ical_feed_url,
    :start_year,
    :end_year,
    :start_date,
    :end_date,
    :source,
    :populated

  validate :all_holidays_valid
  validates_inclusion_of :source, in: %w( suggestions feed )
  validates_presence_of :ical_feed_url,
    if: proc { |holiday_import| holiday_import.source == 'feed' }

  def initialize(opts = {})
    @populated = false
    @start_year = opts.fetch(:start_year, Time.zone.now.year).to_i
    @end_year = opts.fetch(:end_year, Time.zone.now.year).to_i
    @start_date = Date.civil(start_year, 1, 1)
    @end_date = Date.civil(end_year, 12, 31)
    @source = opts.fetch(:source, 'suggestions')
    @ical_feed_url = opts.fetch(:ical_feed_url, nil)
    @country_code = AlaveteliConfiguration.iso_country_code.downcase
    self.holidays_attributes = opts.fetch(:holidays_attributes, [])
  end

  def populate
    source == 'suggestions' ? populate_from_suggestions : populate_from_ical_feed
    @populated = true
  end

  def suggestions_country_name
    IsoCountryCodes.find(@country_code).name if @country_code
  end

  def period
    start_year == end_year ? start_year.to_s : "#{start_year}-#{end_year}"
  end

  def save
    holidays.all?(&:save)
  end

  def save!
    holidays.all?(&:save!)
  end

  def holidays_attributes=(incoming_data)
    incoming_data.each { |_offset, incoming| holidays << Holiday.new(incoming) }
  end

  def holidays
    @holidays ||= []
  end

  private

  def all_holidays_valid
    unless holidays.all?(&:valid?)
      errors.add(:base, 'These holidays could not be imported')
    end
  end

  def populate_from_ical_feed
    cal_file = open(ical_feed_url)
    cal_parser = Icalendar::Parser.new(cal_file)
    cals = cal_parser.parse
    cal = cals.first
    unless cal
      errors.add(:ical_feed_url, "Sorry, there's a problem with the format of that feed.")
      return
    end
    cal.events.each { |cal_event| populate_from_ical_event(cal_event) }
  rescue Errno::ENOENT, Exception => e
    if e.message == 'Invalid line in calendar string!'
      errors.add(:ical_feed_url, "Sorry, there's a problem with the format of that feed.")
    elsif e.message =~ /^No such file or directory/
      errors.add(:ical_feed_url, "Sorry we couldn't find that feed.")
    else
      raise e
    end
  end

  def populate_from_ical_event(cal_event)
    if (cal_event.dtstart >= start_date) && (cal_event.dtstart <= end_date)
      holidays << Holiday.new(description: cal_event.summary,
                              day: cal_event.dtstart)
    end
  end

  def populate_from_suggestions
    holiday_info = Holidays.between(start_date, end_date, @country_code.to_sym, :observed)
    holiday_info.each do |holiday_info_hash|
      holidays << Holiday.new(description: holiday_info_hash[:name],
                              day: holiday_info_hash[:date])
    end
  rescue Holidays::InvalidRegion
    []
  end
end
