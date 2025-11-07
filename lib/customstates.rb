# frozen_string_literal: true

# See `doc/THEMES.md` for more explanation of this file
# This example adds a "transferred" state to requests.

module InfoRequestCustomStates
  def self.included(base)
    base.extend(ClassMethods)
  end

  # Work out what the situation of the request is. In addition to
  # values of self.described_state, in base Alaveteli can return
  # these (calculated) values:
  #   waiting_classification
  #   waiting_response_overdue
  #   waiting_response_very_overdue
  def theme_calculate_status
    # just fall back to the core calculation
    base_calculate_status
  end

  # Mixin methods for InfoRequest
  module ClassMethods
    def theme_display_status(status)
      raise _('unknown status ') + status unless status == 'transferred'

      _('Transferred.')
    end

    def theme_extra_states
      ['transferred']
    end
  end
end

module RequestControllerCustomStates
  def theme_describe_state(info_request)
    # called after the core describe_state code.  It should
    # end by raising an error if the status is unknown
    unless info_request.calculate_status == 'transferred'
      raise "unknown calculate_status #{info_request.calculate_status}"
    end

    flash[:notice] = _('Authority has transferred your request to a different public body.')
    redirect_to request_url(@info_request)
  end
end
