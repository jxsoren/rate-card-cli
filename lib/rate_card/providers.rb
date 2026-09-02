# frozen_string_literal: true

module RateCard
  # Maps a provider key to the object that builds it. Adding a provider later
  # means adding one entry here plus its providers/<name>/ implementation —
  # nothing else here changes.
  module Providers
    REGISTRY = {
      ehub: -> { EHub::Provider.new }
    }.freeze

    module_function

    def all
      REGISTRY.keys
    end

    def build(key)
      REGISTRY.fetch(key) { raise ArgumentError, "unknown provider: #{key}" }.call
    end
  end
end
