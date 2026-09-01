# frozen_string_literal: true

module RateCard
  # Parsing and defaults for the free-text answers. Extracted from Wizard when
  # the prompt flow moved to TUI::App: the parsing is not tied to how the
  # question is asked, and keeping it separate is what lets it be tested
  # without a terminal.
  module Input
    # Fallback only. Valid package types are a property of the service
    # (services[].package_types[].type), so the catalogue is preferred; this
    # covers a catalogue that reports none.
    PACKAGE_TYPES = %w[parcel flat_rate_envelope flat_rate_box soft_pack].freeze
    DEFAULT_WEIGHT_RANGE = '1-16'

    module_function

    # Parses "1-8", "1,3,5" or a mix into a sorted unique Array<Integer>.
    def parse_range(input)
      input.to_s.split(',').flat_map do |part|
        part = part.strip
        if (match = part.match(/\A(\d+)\s*-\s*(\d+)\z/))
          low, high = match.captures.map(&:to_i)
          low <= high ? (low..high).to_a : []
        elsif part.match?(/\A\d+\z/)
          [part.to_i]
        else
          []
        end
      end.uniq.sort
    end
  end
end
