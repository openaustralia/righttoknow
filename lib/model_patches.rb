# frozen_string_literal: true

# Add a callback - to be executed before each request in development,
# and at startup in production - to patch existing app classes.
# Doing so in init/environment.rb wouldn't work in development, since
# classes are reloaded, but initialization is not run each time.
# See http://stackoverflow.com/questions/7072758/plugin-not-reloading-in-development-mode
#
Legislation.class_eval do
  def self.all
    [
      new(
        key: 'foi',
        short: _('FOI'),
        full: _('Freedom of Information'),
        with_a: _('A Freedom of Information request'),
        act: _('Freedom of Information Act'),
        refusals: refusals['foi']
      ),
      new(
        key: 'eir',
        short: _('EIR'),
        full: _('Environmental Information Regulations'),
        with_a: _('An Environmental Information request'),
        act: _('Environmental Information Regulations'),
        refusals: refusals['eir']
      ),
      new(
        key: 'gipa',
        short: _('GIPA'),
        full: _('Government Information (Public Access)'),
        with_a: _('A Government Information (Public Access) request'),
        act: _('Government Information (Public Access) Act'),
        refusals: refusals['gipa'] || []
      ),
      new(
        key: 'rti',
        short: _('RTI'),
        full: _('Right to Information'),
        with_a: _('A Right to Information request'),
        act: _('Right to Information Act'),
        refusals: refusals['rti'] || []
      )
    ]
  end
end

Rails.configuration.to_prepare do
  PublicBody.class_eval do
    def jurisdiction
      if has_tag?('ACT')
        :act
      elsif has_tag?('NSW')
        :nsw
      elsif has_tag?('NT')
        :nt
      elsif has_tag?('QLD')
        :qld
      elsif has_tag?('SA')
        :sa
      elsif has_tag?('TAS')
        :tas
      elsif has_tag?('VIC')
        :vic
      elsif has_tag?('WA')
        :wa
      elsif has_tag?('federal')
        :federal
      end
    end

    def reply_late_after_days
      case jurisdiction
      when :nsw, :tas
        20
      when :qld
        25
      when :federal, :act, :nt, :sa
        30
      when :vic, :wa
        45
      else
        AlaveteliConfiguration.reply_late_after_days
      end
    end

    def working_or_calendar_days
      case jurisdiction
      when :nsw, :tas, :qld
        'working'
      else
        'calendar'
      end
    end

    def info_requests_hidden_count
      info_requests.where('prominence != ?', 'normal').count
    end
  end

  PublicBody.class_eval do
    def legislation
      case jurisdiction
      when :nsw
        Legislation.find!('gipa')
      when :qld, :tas
        Legislation.find!('rti')
      else
        Legislation.find!('foi')
      end
    end
  end

  InfoRequest.class_eval do
    def date_response_required_by
      Holiday.due_date_from(date_initial_request_last_sent_at, public_body.reply_late_after_days,
                            public_body.working_or_calendar_days)
    end
  end
end
