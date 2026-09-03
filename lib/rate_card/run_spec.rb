# frozen_string_literal: true

require 'pathname'
require 'time'

module RateCard
  # Everything one run of the tool needs to know, validated. The wizard's sole
  # output; every component downstream consumes only this. Nothing here prompts
  # or performs I/O.
  #
  # Written as a subclass of an anonymous Struct rather than `Struct.new do ... end`
  # on purpose. Constant *assignment* inside a Struct block resolves lexically, so
  # RATE_KEY_FIELDS there lands on RateCard, not on RunSpec — silently, with no
  # warning — and every external `RunSpec::RATE_KEY_FIELDS` reference then raises
  # NameError. A real class body puts the constants where they belong.
  class RunSpec < Struct.new(
    :token, :customer_name, :customer_id, :carrier, :services, :zones,
    :weight_unit, :weights, :package_type, :rate_keys, :output_base,
    :show_table, :started_at, :rate_mode, :cubic_tiers, :rural,
    :zone_chart, # nil for the 5 static-chart carriers, populated for the live ones
    :country, # nil for domestic; e.g. 'CA' for USPS->Canada — see #origin_for
    keyword_init: true
  )
    # Our rate-key name => the field it arrives as in service_rates. Getting
    # this backwards would put meter rates in the shipper-rate column: a
    # plausible-looking, entirely wrong rate card.
    RATE_KEY_FIELDS = { shipper_rate: 'rate', meter_rate: 'meter_rate' }.freeze
    RATE_KEY_LABELS = { shipper_rate: 'shipper rate', meter_rate: 'meter rate' }.freeze
    WEIGHT_UNITS = %i[oz lbs].freeze

    # One call returns rates for every enabled service, so service count does
    # not affect call volume.
    def call_count
      rows.length * zones.length
    end

    def service_names
      services.map(&:name)
    end

    def rate_key_labels
      rate_keys.map { |key| rate_key_label(key) }
    end

    def zone_summary
      self.class.compact_range(zones)
    end

    def zone_label(zone)
      zone.is_a?(Symbol) ? zone.to_s.upcase : "Z#{zone}"
    end

    # true for USPS with rural mode on, or any UPS surcharge type/combination.
    # nil/false (rural mode off, or a non-rural-aware carrier) is falsy here.
    def rural?
      !!rural
    end

    # true only for USPS->Canada today. nil (domestic, or any other carrier)
    # is falsy here — every existing caller keeps seeing plain domestic
    # behavior.
    def international?
      !!country
    end

    # [1,2,3,5] => "1-3,5". Runs of three or more collapse; a pair stays listed,
    # since "4,5" is no longer than "4-5" and reads as what the user typed.
    #
    # UPS rural mode sweeps surcharge-type symbols (:edas, :rdas) instead of
    # numbered zones - those aren't a range at all, so they're just listed.
    def self.compact_range(numbers)
      array = numbers.to_a
      return array.join(',') if array.any? { |n| n.is_a?(Symbol) }

      sorted = array.sort.uniq
      runs = sorted.slice_when { |a, b| b != a + 1 }.to_a
      runs.map { |run| run.length >= 3 ? "#{run.first}-#{run.last}" : run.join(',') }.join(',')
    end

    # The API always takes ounces; the chosen unit is an input concern only.
    def weight_in_oz(weight)
      weight_unit == :lbs ? weight * 16 : weight
    end

    # Weight mode when not set, so every existing caller — none of which
    # mentions rate_mode — keeps building a weight x zone card exactly as
    # before.
    def rate_mode
      self[:rate_mode] || :weight
    end

    # The row axis Grid/CsvWriter/TableRenderer actually sweep: integer
    # weights in weight mode, selected USPS cubic tier ids in cubic mode.
    # Downstream code reads only this plus #row_label and #row_header, so
    # neither has to know which mode produced it.
    def rows
      rate_mode == :cubic ? cubic_tiers : weights
    end

    def row_label(row)
      rate_mode == :cubic ? Constants::CubicTiers.label(row) : row.to_s
    end

    def row_header
      rate_mode == :cubic ? 'cubic_tier' : 'weight'
    end

    # The weight actually sent on the wire for one row: the tier's fixed
    # cap in cubic mode (cubic pricing is volume-driven, not weight-driven,
    # so the display weight_unit plays no part), or the usual oz/lbs
    # conversion in weight mode.
    def weight_in_oz_for(row)
      rate_mode == :cubic ? Constants::CubicTiers.weight_oz(row) : weight_in_oz(row)
    end

    # nil in weight mode, so Shipment keeps its own fixed nominal box.
    def dims_for(row)
      rate_mode == :cubic ? Constants::CubicTiers.dims(row) : nil
    end

    def validate_rows!
      if rate_mode == :cubic
        raise ArgumentError, 'select at least one cubic tier' if cubic_tiers.nil? || cubic_tiers.empty?

        unknown = cubic_tiers - Constants::CubicTiers.ids
        raise ArgumentError, "unknown cubic tier: #{unknown.join(', ')}" unless unknown.empty?
      else
        raise ArgumentError, 'select at least one weight' if weights.nil? || weights.empty?
      end
    end

    # A Symbol zone (:edas, :rdas) only ever comes from UPS rural mode, so it
    # disambiguates from a real zone number without needing to check carrier
    # or rural separately. USPS rural mode keeps integer zones, just against
    # the rural chart instead of the normal one.
    # USPS->Canada is destination-fixed, origin-varies — the opposite of
    # every other chart here (see #origin_for) — so this returns the one
    # Canadian destination for every zone rather than looking one up per
    # zone.
    def address_for(zone)
      return Constants::Addresses::UPS_RURAL[zone] if zone.is_a?(Symbol)
      return Constants::Addresses::USPS_RURAL_DAS[zone] if carrier == 'USPS' && rural?
      return Constants::Addresses::USPS_CANADA_DESTINATION if usps_canada?
      return zone_chart[zone] if zone_chart

      Constants::Addresses.for_carrier(carrier)[zone]
    end

    # nil for every carrier/zone except USPS->Canada, where the zone is a
    # property of the origin ZIP3 (Usps::IntlGroup1ZoneCalculator), not the
    # destination — see Constants::Addresses::USPS_CANADA_ORIGINS. Shipment
    # falls back to the usual fixed Constants::Addresses::ORIGIN when this
    # is nil, so every other carrier is unaffected.
    def origin_for(zone)
      return nil unless usps_canada?

      Constants::Addresses::USPS_CANADA_ORIGINS[zone]
    end

    def usps_canada?
      carrier == 'USPS' && country == 'CA'
    end

    def rate_key_label(key)
      RATE_KEY_LABELS.fetch(key, key.to_s.tr('_', ' '))
    end

    def weight_label
      rate_mode == :cubic ? 'cubic tier' : "wt(#{weight_unit})"
    end

    # Apostrophes are dropped rather than collapsed, so "Bob's" slugs to "bobs"
    # and not "bob_s". Everything else non-alphanumeric becomes a single
    # underscore. Note the customer name is usually an email address, since eHub
    # tokens carry no customer name.
    def slug
      cleaned = customer_name.to_s.downcase
                             .gsub(/['’`]/, '')
                             .gsub(/[^a-z0-9]+/, '_')
                             .gsub(/\A_+|_+\z/, '')

      # Token always supplies a non-blank name, but an empty slug would build a
      # directory called '_1042_...', so do not rely on that from here.
      cleaned.empty? ? 'customer' : cleaned
    end

    def timestamp
      started_at.utc.strftime('%Y-%m-%dT%H-%M-%SZ')
    end

    def run_dir
      Pathname.new(output_base).join("#{slug}_#{customer_id}_#{timestamp}#{rural_suffix}")
    end

    # UPS rural mode runs one pass per selected surcharge type (see
    # TUI::App#build_specs), so a single spec's zones is exactly one symbol -
    # the suffix names it, so two same-second passes don't collide on
    # run_dir. USPS rural mode sweeps real zones as usual, so it just gets
    # the generic suffix.
    def rural_suffix
      return "_#{country}" if international?
      return '' unless rural?

      surcharge = zones.find { |zone| zone.is_a?(Symbol) }
      surcharge ? "_#{surcharge}" : '_rural'
    end

    def validate!
      raise ArgumentError, 'select at least one service' if services.nil? || services.empty?
      raise ArgumentError, 'select at least one zone' if zones.nil? || zones.empty?
      validate_rows!
      raise ArgumentError, 'select at least one rate column' if rate_keys.nil? || rate_keys.empty?

      unknown = rate_keys - RATE_KEY_FIELDS.keys
      raise ArgumentError, "unknown rate column: #{unknown.join(', ')}" unless unknown.empty?

      unless WEIGHT_UNITS.include?(weight_unit)
        raise ArgumentError, "weight unit must be one of #{WEIGHT_UNITS.join(', ')}"
      end

      zones.each do |zone|
        next if address_for(zone) && (!usps_canada? || origin_for(zone))

        raise ArgumentError, "no address for zone #{zone} on carrier #{carrier}#{" (#{country})" if country}"
      end

      self
    end
  end
end
