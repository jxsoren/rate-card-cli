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

      BY_CARRIER = { 'USPS' => USPS, 'UPS' => UPS, 'FedEx' => FEDEX }.freeze

      module_function

      def for_carrier(carrier)
        BY_CARRIER.fetch(carrier.to_s, USPS)
      end

      def available_zones(carrier)
        for_carrier(carrier).keys.sort
      end
    end
  end
end
