# frozen_string_literal: true

module RateCard
  module Constants
    # Turns the carrier_code that /services reports into the display name the
    # wizard groups by.
    module Carriers
      OTHER = 'Other'

      DISPLAY_ORDER = ['USPS', 'UPS', 'FedEx', 'DHL', 'Amazon', OTHER].freeze

      # Every /services entry carries a lowercase carrier_code. Anything not
      # listed here keeps its own code, upcased: an unrecognised carrier is
      # still better named by itself than lumped into 'Other'.
      #
      # DHL eCommerce reaches /services as 'dhl_ecommerce' and maps to 'DHL'
      # here, aliased to Addresses::USPS because DHL eCommerce's zone
      # calculator in the Rails monolith is a verified unmodified subclass of
      # USPS's zone calculator. The bare 'dhl' code is DHL Express, a distinct
      # carrier with unverified zones, so it gets its own display name
      # ('DHL Express') rather than sharing 'DHL' — with no chart of its own
      # in Addresses, it correctly raises UnsupportedCarrier instead of
      # silently inheriting USPS's zones.
      # Do not add another DHL code to the 'DHL' key unless its zones are
      # likewise verified identical to USPS's — otherwise it needs its own
      # distinct display name here AND its own chart in Addresses, or it will
      # silently inherit the wrong zone chart.
      CARRIER_CODES = {
        'usps' => 'USPS', 'ups' => 'UPS', 'fedex' => 'FedEx',
        'dhl' => 'DHL Express', 'dhl_ecommerce' => 'DHL', 'amazon' => 'Amazon'
      }.freeze

      module_function

      # OTHER is only for a malformed entry with no code at all, so a service is
      # still offered rather than dropped or left with a nil carrier.
      def for_carrier_code(code)
        key = code.to_s.strip.downcase
        return OTHER if key.empty?

        CARRIER_CODES.fetch(key) { key.upcase }
      end

      def display_order
        DISPLAY_ORDER
      end
    end
  end
end
