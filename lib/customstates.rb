# frozen_string_literal: true

# See `doc/THEMES.md` in the host app for more explanation of this file.
#
# Adds the 'external_review' request state: the request is with the
# jurisdiction's external reviewer (for federal authorities, an Information
# Commissioner review at the OAIC). A request enters this state only when an
# external review application is actually sent through the site (see
# ExternalReviewOutgoingMessage in model_patches.rb), and leaves it through
# the ordinary outcome states once the reviewer's decision arrives.
#
# 'transferred' is the example state this file shipped with. It has been
# registered as a valid state on production for years, so it is kept in case
# any request already holds it, but nothing offers it as a choice.

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
    # Our custom states need no time-based recalculation: a request stays in
    # them until it is reclassified, which base_calculate_status handles by
    # returning described_state.
    base_calculate_status
  end

  # Mixin methods for InfoRequest
  module ClassMethods
    def theme_display_status(status)
      case status
      when 'external_review'
        _('Awaiting external review')
      when 'transferred'
        _('Transferred.')
      else
        raise _('unknown status ') + status
      end
    end

    def theme_short_description(status)
      case status
      when 'external_review'
        _('Awaiting external review')
      when 'transferred'
        _('Transferred')
      else
        raise _('unknown status ') + status
      end
    end

    def theme_extra_states
      %w[external_review transferred]
    end
  end
end

module RequestControllerCustomStates
  def theme_describe_state(info_request)
    # called after the core describe_state code. It should
    # end by raising an error if the status is unknown
    case info_request.calculate_status
    when 'external_review'
      # The advice flash was already set from
      # request/describe_notices/_external_review if present, so just
      # redirect back to the request.
      redirect_to request_url(info_request)
    when 'transferred'
      flash[:notice] = _('Authority has transferred your request to a different public body.')
      redirect_to request_url(info_request)
    else
      raise "unknown calculate_status #{info_request.calculate_status}"
    end
  end
end
