# models/track_mailer.rb:
# Emails which go to users who are tracking things.
#
# Copyright (c) 2008 UK Citizens Online Democracy. All rights reserved.
# Email: hello@mysociety.org; WWW: http://www.mysociety.org/

class TrackMailer < ApplicationMailer
  helper UnsubscribeHelper

  before_action :set_footer_template, only: :event_digest

  # Note that this is different from all the other mailers, as tracks are
  # sent from a different email address and have different bounce handling.
  def contact_from_name_and_email
    "#{AlaveteliConfiguration.track_sender_name} <#{AlaveteliConfiguration.track_sender_email}>"
  end

  def event_digest(user, email_about_things)
    @user = user
    @email_about_things = email_about_things

    headers(
      # http://tools.ietf.org/html/rfc3834
      'Auto-Submitted' => 'auto-generated',
      # http://www.vbulletin.com/forum/project.php?issueid=27687
      # (Exchange hack)
      'Precedence' => 'bulk'
    )

    # 'Return-Path' => blackhole_email, 'Reply-To' => @from # we don't care about bounces for tracks
    # (We let it return bounces for now, so we can manually kill the tracks that bounce so Yahoo
    # etc. don't decide we are spammers.)

    mail(from: contact_from_name_and_email,
         to: user.name_and_email,
         subject: _("Your {{site_name}} email alert",
                       site_name: site_name.html_safe))
  end

  # Send email alerts for tracked things.  Never more than one email
  # a day, nor about events which are more than a week old, nor
  # events about which emails have been sent within the last two
  # weeks.

  # Useful query to run by hand to see how many alerts are due:
  #   User.where("last_daily_track_email < ?", Time.zone.now - 1.day).size
  def self.alert_tracks
    done_something = false
    now = Time.zone.now
    one_week_ago = now - 7.days
    User.where(["last_daily_track_email < ?", now - 1.day ]).find_each do |user|
      next unless user.should_be_emailed?

      email_about_things = []
      track_things = TrackThing.where(tracking_user_id: user.id,
                                      track_medium: 'email_daily')
      track_things.each do |track_thing|
        # What have we alerted on already?
        #
        # We only use track_things_sent_emails records which are less than 14 days old.
        # In the search query loop below, we also only use items described in last 7 days.
        # An item described that recently definitely can't appear in track_things_sent_emails
        # earlier, so this is safe (with a week long margin of error). If the alerts break
        # for a whole week, then they will miss some items. Tough.
        done_info_request_events = {}
        tt_sent = track_thing.track_things_sent_emails.where('created_at > ?', now - 14.days)
        tt_sent.each do |t|
          unless t.info_request_event_id.nil?
            done_info_request_events[t.info_request_event_id] = 1
          end
        end

        # Query for things in this track. We use described_at for the
        # ordering, so we catch anything new (before described), or
        # anything whose new status has been described.
        xapian_object = ActsAsXapian::Search.new([InfoRequestEvent], track_thing.track_query,
                                                 sort_by_prefix: 'described_at',
                                                 sort_by_ascending: true,
                                                 collapse_by_prefix: nil,
                                                 limit: 100)
        # Go through looking for unalerted things
        alert_results = []
        xapian_object.results.each do |result|
          if result[:model].class.to_s != "InfoRequestEvent"
            raise "need to add other types to TrackMailer.alert_tracks (unalerted)"
          end

          if track_thing.created_at >= result[:model].described_at  # made before the track was created
            next
          end
          if result[:model].described_at < one_week_ago  # older than 1 week (see 14 days / 7 days in comment above)
            next
          end
          if done_info_request_events.include?(result[:model].id)  # definitely already done
            next
          end

          # OK alert this one
          alert_results.push(result)
        end
        # If there were more alerts for this track, then store them
        if !alert_results.empty?
          email_about_things.push([track_thing, alert_results, xapian_object])
        end
      end

      # If we have anything to send, then send everything for the user in one mail
      if !email_about_things.empty?
        # Send the email

        AlaveteliLocalization.with_locale(user.locale) do
          TrackMailer.event_digest(user, email_about_things).deliver_now
        end
      end

      # Record that we've now sent those alerts to that user
      email_about_things.each do |track_thing, alert_results|
        alert_results.each do |result|
          track_things_sent_email = TrackThingsSentEmail.new
          track_things_sent_email.track_thing_id = track_thing.id
          if result[:model].class.to_s == "InfoRequestEvent"
            track_things_sent_email.info_request_event_id = result[:model].id
          else
            raise "need to add other types to TrackMailer.alert_tracks (mark alerted)"
          end
          track_things_sent_email.save!
        end
      end
      user.last_daily_track_email = now
      user.no_xapian_reindex = true
      user.save!(touch: false)
      done_something = true
    end
    done_something
  end

  def self.alert_tracks_loop
    # Run alert_tracks in an endless loop, sleeping when there is nothing to do
    loop do
      sleep_seconds = 1
      until alert_tracks
        sleep sleep_seconds
        sleep_seconds *= 2
        sleep_seconds = 300 if sleep_seconds > 300
      end
    end
  end

  private

  def set_footer_template
    @footer_template = 'default_with_unsubscribe'
  end

end
