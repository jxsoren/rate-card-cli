# frozen_string_literal: true

module RateCard
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

    def initialize(spec:, weight:, address:)
      @spec = spec
      @weight = weight
      @address = address
    end

    def payload
      {
        shipment: {
          from_location: Constants::Addresses::ORIGIN,
          to_location: to_location,
          parcels: [parcel]
        }
      }
    end

    private

    attr_reader :spec, :weight, :address

    def to_location
      {
        company: 'Rate Card Builder',
        phone: '000-000-0000'
      }.merge(address)
    end

    def parcel
      {
        package_type: spec.package_type,
        length: DIMENSION,
        width: DIMENSION,
        height: DIMENSION,
        weight: spec.weight_in_oz(weight),
        parcel_items: [parcel_item],
        customs_data: customs_data
      }
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
