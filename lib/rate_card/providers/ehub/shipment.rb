# frozen_string_literal: true

module RateCard
  module Providers
    module EHub
      # Builds the request body for one (weight, zone) rate call.
      #
      # The shape follows the documented rate request
      # (https://docs.ehub.com/rates/rate-request). The customs blocks are sent even
      # for domestic cards because international services error without them; the
      # docs mark the parcel-level one as required for international shipments.
      class Shipment
        DIMENSION = 2
        ITEM_VALUE = 18.99
        HS_TARIFF_CODE = '1704.90.3000'

        # origin: nil for every carrier except USPS->Canada, where the zone is
        # a property of the origin rather than the destination — see
        # RunSpec#origin_for. Falls back to the usual fixed shipment origin
        # when nil, so every other carrier is unaffected.
        def initialize(spec:, weight:, address:, origin: nil)
          @spec = spec
          @weight = weight
          @address = address
          @origin = origin
        end

        def payload
          {
            shipment: {
              from_location: origin || Constants::Addresses::ORIGIN,
              to_location: to_location,
              parcels: [parcel]
            }
          }
        end

        private

        attr_reader :spec, :weight, :address, :origin

        def to_location
          {
            company: 'Rate Card Builder',
            phone: '000-000-0000'
          }.merge(address)
        end

        def parcel
          box = dims
          {
            package_type: spec.package_type,
            length: box[:length],
            width: box[:width],
            height: box[:height],
            weight: spec.weight_in_oz_for(weight),
            parcel_items: [parcel_item],
            customs_data: customs_data
          }
        end

        def dims
          spec.dims_for(weight) || { length: DIMENSION, width: DIMENSION, height: DIMENSION }
        end

        # The parcel as a whole. One item at quantity 1, so this mirrors the item's
        # declaration; the docs require it for international shipments.
        def customs_data
          {
            content_type: 'merchandise',
            value: ITEM_VALUE,
            hs_tariff_code: HS_TARIFF_CODE
          }
        end

        def parcel_item
          {
            name: 'Candy',
            quantity: 1,
            price: ITEM_VALUE,
            customs_data: customs_data
          }
        end
      end
    end
  end
end
