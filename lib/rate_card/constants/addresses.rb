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

      # UNVERIFIED — real public post-office addresses, one per origin ZIP3
      # that Usps::IntlGroup1ZoneCalculator (ehub app/services/usps/
      # intl_group1_zone_calculator.rb, backed by
      # files/usps_intl_canada_zones.json.gz) maps to each zone 1-8.
      #
      # USPS's Canada rate is origin-driven, not destination-driven like the
      # domestic charts above: the zone comes from the FROM zip's first 3
      # digits, and the destination only needs to be a real address in
      # Canada (see the spec fixtures in usps/rate_calculator_spec.rb, which
      # call rate(from_zip, 'CA', ...) - no street-level destination enters
      # the calculation at all). That inverts RunSpec#address_for's usual
      # "vary destination, fix origin" shape for this one carrier/country
      # pair - see #origin_for.
      #
      # Addresses are real (each is a public USPS post office and its ZIP3
      # was confirmed against the actual origin table, not just "a nearby
      # city"), but UNVERIFIED means the ZIP3 -> zone mapping itself hasn't
      # been re-derived from files/usps_intl_canada_zones.json.gz by a
      # second person - do this before trusting a rate card built from it.
      USPS_CANADA_ORIGINS = {
        1 => { address1: '1040 Waverly Ave', city: 'Holtsville', state: 'NY', postal_code: '00501', country: 'US' },
        2 => { address1: '600 Suffield St', city: 'Agawam', state: 'MA', postal_code: '01001', country: 'US' },
        3 => { address1: '462 Washington St', city: 'Woburn', state: 'MA', postal_code: '01801', country: 'US' },
        4 => { address1: '73 Hammond St Ste 9998', city: 'Bangor', state: 'ME', postal_code: '04401', country: 'US' },
        5 => { address1: '83 Broad St', city: 'Charleston', state: 'SC', postal_code: '29401', country: 'US' },
        6 => { address1: '50 Carr 459', city: 'Aguadilla', state: 'PR', postal_code: '00603', country: 'US' },
        7 => { address1: '709 W 9th St', city: 'Juneau', state: 'AK', postal_code: '99801', country: 'US' },
        8 => { address1: '99-040 Kauhale St', city: 'Aiea', state: 'HI', postal_code: '96701', country: 'US' }
      }.freeze

      # UNVERIFIED — the fixed Canadian destination for every USPS_CANADA_ORIGINS
      # zone. Ported from INTERNATIONAL_UNVERIFIED zone 0 below. Safe to reuse
      # across all 8 zones only because USPS's Canada rate doesn't depend on
      # destination specifics - see USPS_CANADA_ORIGINS above. Do not reuse
      # this reasoning for any other carrier without checking that carrier's
      # own calculator the same way.
      USPS_CANADA_DESTINATION = { address1: '6990 Victoria Dr', city: 'Vancouver', state: 'BC',
                                   postal_code: 'V5P 3Y8', country: 'CA' }.freeze

      # UNVERIFIED — ported as-is from ../rate_table_builder/constants/address_constants.rb
      # (INTL_ADDRESSES, originally commented "# International?"). Not
      # confirmed against any carrier's actual international zone chart, and
      # not carrier-specific: the source file left international: nil for
      # USPS, UPS, and FedEx alike, so these zone numbers are not known to
      # correspond to DHL Express, DHL eCommerce, or USPS Priority Mail
      # International zone boundaries. Do not wire this into BY_CARRIER or
      # for_carrier until each entry is hand-verified against a real
      # carrier zone chart, the way the domestic addresses above are.
      INTERNATIONAL_UNVERIFIED = [
        { zone: 0, address1: '6990 Victoria Dr', city: 'Vancouver', state: 'Vancouver', postal_code: 'V5P 3Y8', country: 'CA' },
        { zone: 1, address1: '1249 Metcalfe St', city: 'Montreal', state: 'Montreal', postal_code: 'H3B 2V5', country: 'CA' },
        { zone: 2, address1: '10416 80 Ave NW', city: 'Edmonton', state: 'Edmonton', postal_code: 'T6E 5T7', country: 'CA' },
        { zone: 3, address1: '4910 52 St', city: 'Yellowknife', state: 'Yellowknife', postal_code: 'X1A 1T3', country: 'CA' },
        { zone: 4, address1: '179 Shaftesbury Ave', city: 'London', state: 'London', postal_code: 'WC2H 8JR', country: 'GB' },
        { zone: 5, address1: 'R Sao Joaquim, 381 - Liberdade', city: 'Sao Paulo', state: 'Sao Paulo', postal_code: '01508-001', country: 'BR' },
        { zone: 6, address1: '10 Bligh St', city: 'Sydney', state: 'Sydney', postal_code: '2000', country: 'AU' },
        { zone: 7, address1: 'Rudi-Dutschke-Strasse 26', city: 'Berlin', state: 'Berlin', postal_code: '10969', country: 'DE' },
        { zone: 8, address1: '107 Rue de Rivoli', city: 'Paris', state: 'Paris', postal_code: '75001', country: 'FR' },
        { zone: 9, address1: 'Colima 150, Roma Nte.', city: 'Mexico City', state: 'Mexico City', postal_code: '06700', country: 'MX' },
        { zone: 10, address1: '18 Merrion Row', city: 'Dublin', state: 'Dublin', postal_code: 'D02 A316', country: 'IE' },
        { zone: 11, address1: '3 Chome-4 Kagurazaka', city: 'Tokyo', state: 'Tokyo', postal_code: '162-0825', country: 'JP' },
        { zone: 12, address1: '90 Wellesley Street West', city: 'Auckland', state: 'Auckland', postal_code: '1010', country: 'NZ' },
        { zone: 13, address1: 'Munsterhof 12,', city: 'Zurich', state: 'Zurich', postal_code: '8001', country: 'CH' },
        { zone: 14, address1: 'Daniel Stalpertstraat 103', city: 'Amsterdam', state: 'Amsterdam', postal_code: '1072', country: 'NL' },
        { zone: 15, address1: '404 Crescent Business Park Link Road Andheri', city: 'Mumbai', state: 'Maharashtra', postal_code: '400072', country: 'IN' },
        { zone: 16, address1: 'C. del Prado, 16', city: 'Madrid', state: 'Madrid', postal_code: '28014', country: 'ES' },
        { zone: 17, address1: 'Piazza Pasquale Paoli 15', city: 'Roma', state: 'Roma', postal_code: '00186', country: 'IT' }
      ].freeze

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
