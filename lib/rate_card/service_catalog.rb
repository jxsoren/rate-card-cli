# frozen_string_literal: true

module RateCard
  # Turns a rate response's service_rates array into the list of services this
  # customer actually has enabled. Used on the probe call so the wizard never
  # offers a service the customer does not have, and never relies on a
  # hardcoded service id that has since drifted.
  module ServiceCatalog
    module_function

    # Returns Array<Service>, de-duplicated and sorted for display.
    def from_response(body)
      entries = body.is_a?(Hash) ? (body['service_rates'] || []) : []

      services = entries.filter_map { |entry| build_service(entry) }.uniq(&:id)
      sort_for_display(services)
    end

    # Returns { carrier => Array<Service> } with carriers in display order.
    def group_by_carrier(services)
      services.group_by(&:carrier)
              .sort_by { |carrier, _| carrier_rank(carrier) }
              .to_h
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
        carrier: entry['carrier'] || Constants::Carriers.for_service_id(id)
      )
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
