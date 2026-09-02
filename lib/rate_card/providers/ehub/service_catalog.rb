# frozen_string_literal: true

module RateCard
  module Providers
    module EHub
      # Turns the /services response into the list of services the wizard can offer.
      # Read live rather than from a hardcoded list so a service id that has drifted
      # cannot silently produce a card of blank cells.
      module ServiceCatalog
        module_function

        # Returns Array<Service>, de-duplicated and sorted for display.
        def from_response(body)
          entries = body.is_a?(Hash) ? (body['services'] || []) : []

          services = entries.filter_map { |entry| build_service(entry) }.uniq(&:id)
          sort_for_display(services)
        end

        def build_service(entry)
          id = entry['service_id']
          return nil if id.nil?

          code = entry['service_code'].to_s
          name = entry['service'].to_s
          name = code if name.strip.empty?

          Service.new(
            id: id.to_i,
            code: code,
            name: name,
            carrier: Constants::Carriers.for_carrier_code(entry['carrier_code']),
            package_types: package_types(entry)
          )
        end

        # services[].package_types is an array of {type, name}; only the type is
        # sent back in a rate request.
        def package_types(entry)
          Array(entry['package_types']).filter_map do |package_type|
            next package_type.to_s unless package_type.is_a?(Hash)

            type = package_type['type'].to_s
            type.empty? ? nil : type
          end.uniq
        end

        def sort_for_display(services)
          services.sort_by { |service| [carrier_rank(service.carrier), service.name.to_s] }
        end

        def carrier_rank(carrier)
          index = Constants::Carriers.display_order.index(carrier)
          index || Constants::Carriers.display_order.length
        end
      end
    end
  end
end
