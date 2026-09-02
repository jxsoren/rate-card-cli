# frozen_string_literal: true

module RateCard
  module Constants
    # Hand-verified destination addresses, one per zone per carrier. Zone
    # membership is a property of a real address and a real carrier's zone chart,
    # so these are curated by hand and never derived at runtime.
    #
    # Ported from ../rate_table_builder/constants/address_constants.rb.
    #
    # One deliberate normalisation: that file spells 130 Braewick Rd / 84103 as
    # 'SLC' in its USPS table and 'Salt Lake City' in its UPS table. We use
    # 'Salt Lake City' in both. Zone membership follows the postal code, and we
    # send validation_level 'basic', which some address validators fail on the
    # abbreviation. Do not "restore" 'SLC'.
    module Addresses
      ORIGIN = {
        company: 'Rate Card Builder',
        address1: '9490 S 300 W',
        city: 'Sandy',
        state: 'UT',
        postal_code: '84070',
        country: 'US',
        phone: '000-000-0000'
      }.freeze

      USPS = {
        1 => { address1: '1206 W 9440 S', city: 'South Jordan', state: 'UT', postal_code: '84094', country: 'US' },
        2 => { address1: '130 Braewick Rd', city: 'Salt Lake City', state: 'UT', postal_code: '84103', country: 'US' },
        3 => { address1: '1526 21st St', city: 'Cody', state: 'WY', postal_code: '82414', country: 'US' },
        4 => { address1: '1954 E Fountain St', city: 'Mesa', state: 'AZ', postal_code: '85203', country: 'US' },
        5 => { address1: '2909 Woodland Ave', city: 'West Des Moines', state: 'IA', postal_code: '50266', country: 'US' },
        6 => { address1: '19813 Crescent Ave', city: 'Lynwood', state: 'IL', postal_code: '60411', country: 'US' },
        7 => { address1: '922 Maple Ave', city: 'Pittsburgh', state: 'PA', postal_code: '15234', country: 'US' },
        8 => { address1: '3149 Brickell Ave', city: 'Miami', state: 'FL', postal_code: '33129', country: 'US' }
      }.freeze

      UPS = {
        1 => { address1: '9121 S Village Shop D', city: 'Sandy', state: 'UT', postal_code: '84094', country: 'US' },
        2 => { address1: '130 Braewick Rd', city: 'Salt Lake City', state: 'UT', postal_code: '84103', country: 'US' },
        3 => { address1: '1526 21st St', city: 'Cody', state: 'WY', postal_code: '82414', country: 'US' },
        4 => { address1: '1954 E Fountain St', city: 'Mesa', state: 'AZ', postal_code: '85203', country: 'US' },
        5 => { address1: '2909 Woodland Ave', city: 'West Des Moines', state: 'IA', postal_code: '50266', country: 'US' },
        6 => { address1: '19813 Crescent Ave', city: 'Lynwood', state: 'IL', postal_code: '60411', country: 'US' },
        7 => { address1: '922 Maple Ave', city: 'Pittsburgh', state: 'PA', postal_code: '15234', country: 'US' },
        8 => { address1: '3149 Brickell Ave', city: 'Miami', state: 'FL', postal_code: '33129', country: 'US' }
      }.freeze

      FEDEX = {
        1 => { address1: '50 S Main Street', city: 'Salt Lake City', state: 'UT', postal_code: '84101', country: 'US' },
        2 => { address1: '1700 Lincoln Street', city: 'Denver', state: 'CO', postal_code: '80203', country: 'US' },
        3 => { address1: '411 E Wisconsin Avenue', city: 'Phoenix', state: 'AZ', postal_code: '85004', country: 'US' },
        4 => { address1: '1201 Elm Street', city: 'Dallas', state: 'TX', postal_code: '75270', country: 'US' },
        5 => { address1: '233 S Wacker Drive', city: 'Chicago', state: 'IL', postal_code: '60606', country: 'US' },
        6 => { address1: '191 Peachtree Street NE', city: 'Atlanta', state: 'GA', postal_code: '30303', country: 'US' },
        7 => { address1: '350 Fifth Avenue', city: 'New York', state: 'NY', postal_code: '10118', country: 'US' },
        8 => { address1: '1 Beacon Street', city: 'Boston', state: 'MA', postal_code: '02108', country: 'US' }
      }.freeze

      # DHL eCommerce's zone calculator (ehub's
      # app/services/carriers/dhl_ecommerce/zone_calculator.rb) is an
      # unmodified subclass of USPS's zone calculator, so DHL eCommerce
      # zones are USPS zones. This is the same chart, not a coincidence to
      # keep in sync by hand - if DHL eCommerce ever gets its own zone
      # calculator, split this back into its own hand-verified hash.
      DHL_ECOMMERCE = USPS

      # OSM's zone calculator in ehub (app/services/carriers/osm/zone_calculator.rb)
      # is likewise an unmodified subclass of USPS's, so OSM zones are USPS
      # zones - same reasoning as DHL_ECOMMERCE above.
      OSM = USPS

      BY_CARRIER = { 'USPS' => USPS, 'UPS' => UPS, 'FedEx' => FEDEX, 'DHL' => DHL_ECOMMERCE, 'OSM' => OSM }.freeze

      # Rural/remote-area surcharge test addresses. These aren't zone charts
      # (rural surcharge eligibility is a property of the destination zip on
      # a carrier's rural list, not something for_carrier's zone lookup
      # models), so they live outside BY_CARRIER and are looked up directly
      # by callers that need them.
      #
      # Ported from ../rate_table_builder/constants.rb. USPS_RURAL_DAS zones
      # 4-8 were tagged 'maybe' or unverified in the source file - re-verify
      # against USPS's rural lookup before relying on them for a real card.
      USPS_RURAL_DAS = {
        0 => { address1: '12078 W 4000 N', city: 'Bluebell', state: 'UT', postal_code: '84007', country: 'US' },
        1 => { address1: '6074 N 4700 W', city: 'Bear River City', state: 'UT', postal_code: '84301', country: 'US' },
        2 => { address1: '25670 Buffalo Run', city: 'Moran', state: 'WY', postal_code: '83013', country: 'US' },
        3 => { address1: '17 Texs Loop', city: 'Alder', state: 'MT', postal_code: '59710', country: 'US' },
        4 => { address1: '1250 153rd St SE', city: 'Norwich', state: 'ND', postal_code: '58768', country: 'US' },
        5 => { address1: '103 Stonegate Ct', city: 'Gurdon', state: 'AR', postal_code: '71743', country: 'US' },
        6 => { address1: '31 Edsel Rd', city: 'Webbville', state: 'KY', postal_code: '41180', country: 'US' },
        7 => { address1: '295 Old Waterford Road', city: 'Littleton', state: 'NH', postal_code: '03561', country: 'US' },
        8 => { address1: '77 Main Street', city: 'Mars Hill', state: 'ME', postal_code: '04758', country: 'US' }
      }.freeze

      # UPS has no per-zone rural chart - just one known address per DAS
      # variant. EDAS = Extended Delivery Area Surcharge, RDAS = Remote
      # Delivery Area Surcharge.
      UPS_EDAS_EXCEPTION = { address1: '149 Pheasant Runn Road', city: 'Goshen', state: 'NH', postal_code: '03752',
                              country: 'US' }.freeze

      UPS_RDAS_EXCEPTION = { address1: '106 Yellow Hammer Rd', city: 'Tyner', state: 'NC', postal_code: '27980',
                              country: 'US' }.freeze

      # Looked up by surcharge-type symbol rather than zone, since UPS rural
      # mode sweeps surcharge types instead of zones — see RunSpec#address_for.
      UPS_RURAL = { edas: UPS_EDAS_EXCEPTION, rdas: UPS_RDAS_EXCEPTION }.freeze

      module_function

      # Raises rather than falling back. The old USPS default meant asking for
      # a carrier we have no chart for produced a full, plausible-looking card
      # priced to USPS zone addresses and labeled Z1-Z8 — wrong in a way
      # nothing downstream could detect. A missing chart is a missing chart.
      def for_carrier(carrier)
        BY_CARRIER.fetch(carrier.to_s) do
          raise UnsupportedCarrier,
                "no curated zone chart for #{carrier} — rate cards are only " \
                "available for #{supported_carriers.join(', ')}. Adding one means " \
                "hand-verifying a destination address per zone against that " \
                'carrier\'s own zone chart and adding it to Addresses::BY_CARRIER.'
        end
      end

      def supported?(carrier)
        BY_CARRIER.key?(carrier.to_s)
      end

      def supported_carriers
        BY_CARRIER.keys
      end

      # [] for a carrier with no chart, so the wizard can ask about zones
      # without having to rescue.
      def available_zones(carrier)
        supported?(carrier) ? for_carrier(carrier).keys.sort : []
      end
    end
  end
end
