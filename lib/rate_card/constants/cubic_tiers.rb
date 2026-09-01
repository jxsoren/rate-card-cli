# frozen_string_literal: true

module RateCard
  module Constants
    # The ten official USPS cubic-pricing tiers (Ground Advantage Cubic,
    # Priority Mail Cubic): the tier a package prices under is decided by
    # which bounding cube its dimensions fit inside, not by its weight — so
    # each tier pairs a fixed cube with the weight cap USPS prices it under.
    # Ported from ../../rate_table_builder/constants.rb's CUBIC_PARAMS.
    module CubicTiers
      TIERS = [
        { tier: 1,  length: 3.0,   width: 3.0,   height: 3.0,   weight_oz: 128 },
        { tier: 2,  length: 6.0,   width: 6.0,   height: 6.0,   weight_oz: 128 },
        { tier: 3,  length: 7.5,   width: 7.5,   height: 7.5,   weight_oz: 128 },
        { tier: 4,  length: 8.5,   width: 8.5,   height: 8.5,   weight_oz: 128 },
        { tier: 5,  length: 9.0,   width: 9.0,   height: 9.0,   weight_oz: 128 },
        { tier: 6,  length: 10.0,  width: 10.0,  height: 10.0,  weight_oz: 128 },
        { tier: 7,  length: 10.5,  width: 10.5,  height: 10.5,  weight_oz: 128 },
        { tier: 8,  length: 11.0,  width: 11.0,  height: 11.0,  weight_oz: 128 },
        { tier: 9,  length: 11.25, width: 11.25, height: 11.25, weight_oz: 240 },
        { tier: 10, length: 11.75, width: 11.75, height: 11.75, weight_oz: 240 }
      ].freeze

      module_function

      def ids
        TIERS.map { |t| t[:tier] }
      end

      def find(tier_id)
        TIERS.find { |t| t[:tier] == tier_id }
      end

      def dims(tier_id)
        tier = find(tier_id)
        return nil unless tier

        { length: tier[:length], width: tier[:width], height: tier[:height] }
      end

      def weight_oz(tier_id)
        find(tier_id)&.fetch(:weight_oz)
      end

      def label(tier_id)
        "Tier #{tier_id}"
      end

      # One display choice per tier, for the wizard's multi-select, e.g.
      # ["Tier 1 — 3x3x3in, ≤8lb", 1].
      def choices
        TIERS.map { |t| [choice_label(t), t[:tier]] }
      end

      def choice_label(tier)
        dims_label = "#{fmt(tier[:length])}x#{fmt(tier[:width])}x#{fmt(tier[:height])}in"
        "#{label(tier[:tier])} — #{dims_label}, ≤#{tier[:weight_oz] / 16}lb"
      end

      # Trims a whole-number float's trailing ".0" so tier labels read "3x3x3in"
      # rather than "3.0x3.0x3.0in".
      def fmt(number)
        number == number.to_i ? number.to_i.to_s : number.to_s
      end
    end
  end
end
