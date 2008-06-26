class Timeslot < ActiveRecord::Base
  belongs_to :room
  belongs_to :conference
  has_many :proposals
  has_many :attendances
  has_and_belongs_to_many :prop_types

  validates_presence_of :start_time
  validates_presence_of :room_id
  validates_presence_of :conference_id
  validates_associated :room, :conference
  validate :during_conference_days

  # Returns a paginated list with all of the timeslots for the
  # specified date, ordered by start time
  def self.for_day(date, req={})
    self.paginate(:all, 
                  {:conditions => ['start_time BETWEEN ? and ?',
                                  date.beginning_of_day, date.end_of_day],
                    :order => :start_time,
                    :page => 1}.merge(req))
  end

  # Produce a paginated list of timeslots, ordered by the absolute
  # distance between their start_time and the current time. 
  #
  # It can take whatever parameters you would send to a
  # WillPaginate#paginate call. Of course, you can specify a different
  # ordering - in which case this would act as a normal paginator 
  def self.by_time_distance(req={})
    self.paginate(:all, 
                  { :order => 'CASE WHEN start_time > now() THEN start_time ' +
                    ' - now() ELSE now() - start_time END',
                    :page => 1}.merge(req))
  end

  # Returns the list of current timeslots - those for which attendance
  # can be taken now. This means, those timeslots for which the
  # current system clock is between tolerance_pre and
  # tolerance_post. If either of them is not defined, we take the
  # globally configured values in SysConf, or if neither they are
  # present, 30 minutes.
  def self.current
    self.find(:all, :conditions => 
              [%Q(now() BETWEEN start_time - coalesce(tolerance_pre, ?, 
                        '30 minutes')::interval AND start_time +
                        coalesce(tolerance_post, ?, '30 minutes')::interval ),
               SysConf.value_for('tolerance_pre'),
               SysConf.value_for('tolerance_post')] )
  end

  # An easier-on-the-eyes format...
  def short_start_time
    start_time.strftime('%d-%m-%Y %H:%M')
  end

  # Intervals in Ruby are represented as a semi-opaque "thing" that
  # becomes an integer number of seconds when needed... Treating them
  # in any other way breaks applications. So, as soon as we get them,
  # stringify them to something PostgreSQL will grok.
  def tolerance_pre=(time)
    self[:tolerance_pre] = interval_to_seconds(time)
  end

  def tolerance_post=(time)
    self[:tolerance_post] = interval_to_seconds(time)
  end

  protected
  def interval_to_seconds(time)
    # A nil is a nil is a nil. And if the interval includes a ':',
    # Postgres will grok it better than me.
    return time if time.nil? or time=~/:/
    seconds = time.to_i
    if seconds >= 2**31 or seconds <= -2**31
      raise TypeError, "#{time} interval out of range" 
    end
    "#{seconds} seconds"
  end

  def during_conference_days
    conf = self.conference
    return true if start_time.to_date.between?(conf.begins,
                                               conf.finishes)
    errors.add(:start_time, _('Must start within the conference dates ' +
                              '(%s - %s)') % [conf.begins, conf.finishes])
  end
end
