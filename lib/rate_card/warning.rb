# frozen_string_literal: true

module RateCard
  # One distinct thing the API told us went wrong, with how many calls said it.
  #
  # Deliberately not keyed by (weight, zone) the way Failure is: a carrier
  # outage repeats the same message on all 128 calls, and the user needs the
  # message once, not a wall of it.
  Warning = Struct.new(:message, :count, keyword_init: true)
end
