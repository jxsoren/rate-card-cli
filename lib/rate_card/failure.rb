# frozen_string_literal: true

module RateCard
  # One rate call that did not succeed. Keyed by (weight, zone) rather than by
  # service, because a single call covers every selected service — when it
  # fails, they all lose the same cell.
  Failure = Struct.new(:weight, :zone, :message, keyword_init: true)
end
