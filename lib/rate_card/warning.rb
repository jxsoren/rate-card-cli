# frozen_string_literal: true

module RateCard
  # One distinct thing the API told us went wrong, with how many calls said it.
  #
  # Deliberately not keyed by (weight, zone) the way Failure is: a carrier
  # outage repeats the same message on all 128 calls, and the user needs the
  # message once, not a wall of it.
  #
  # `scope` is what the message can be blamed on. :service means it came from
  # the `errors` field of a service in this card, so it explains that service's
  # blank cells. :account means it came from the response-level `warnings`
  # array, which covers every service enabled on the token — one call rates all
  # of them — so it may be about a service nobody asked for. It is still
  # reported, not filtered: 'Unable to verify address' arrives at response level
  # and is about this card's own destination address.
  class Warning < Struct.new(:message, :count, :scope, keyword_init: true)
    SERVICE = :service
    ACCOUNT = :account

    # Service-scoped is the safe default: it says 'this is about what you
    # selected', which is the claim a caller that did not set a scope is making.
    def scope
      self[:scope] || SERVICE
    end

    def account_wide?
      scope == ACCOUNT
    end
  end
end
