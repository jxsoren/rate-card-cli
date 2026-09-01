# frozen_string_literal: true

module RateCard
  # Builds the request body for one (weight, zone) rate call.
  #
  # The shape is copied from ../rate_sheet_builder/default_builder.rb, which is
  # known to succeed against production. The parcel_items customs block is kept
  # even for domestic cards because international services error without it.
  class Shipment
    DIMENSION = 2
    ITEM_VALUE = 18.99

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
        phone: '000-000-0000',
        validation_level: 'basic'
      }.merge(address)
    end

    def parcel
      {
        package_type: spec.package_type,
        length: DIMENSION,
        width: DIMENSION,
        height: DIMENSION,
        weight: spec.weight_in_oz(weight),
        parcel_items: [parcel_item]
      }
    end

    def parcel_item
      {
        name: 'Candy',
        quantity: 1,
        price: ITEM_VALUE,
        customs_data: {
          content_type: 'merchandise',
          value: ITEM_VALUE,
          hs_tariff_code: '1704.90.3000'
        }
      }
    end
  end
end
