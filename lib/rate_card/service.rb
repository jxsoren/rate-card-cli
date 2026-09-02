# frozen_string_literal: true

module RateCard
  # One shipping service the customer has enabled, as discovered from a probe call.
  Service = Struct.new(:id, :code, :name, :carrier, :package_types, keyword_init: true) do
    # Returns { carrier => Array<Service> } with carriers in display order.
    # Provider-agnostic: any provider's #parse_services returns these same
    # structs, so grouping them for display doesn't belong to any one provider.
    def self.group_by_carrier(services)
      services.group_by(&:carrier)
              .sort_by { |carrier, _| carrier_rank(carrier) }
              .to_h
    end

    def self.carrier_rank(carrier)
      index = Constants::Carriers.display_order.index(carrier)
      index || Constants::Carriers.display_order.length
    end

    # The package types this service accepts, from services[].package_types.
    # Always an array: callers offer these as choices, and a nil would have to
    # be guarded at every one of them.
    def package_types
      Array(self[:package_types])
    end

    # What the wizard checkbox shows.
    def label
      "#{name} (#{id})"
    end

    # Basis for output filenames; must be filesystem-safe and never empty.
    #
    # Falls through on the SANITISED value, not the raw one: a code like '###'
    # is non-empty but sanitises to nothing, and an empty slug would produce a
    # file named '_shipper_rate.csv' on the user's disk.
    def file_slug
      [code, name].each do |candidate|
        slug = sanitize(candidate)
        return slug unless slug.empty?
      end

      sanitize("service_#{id}")
    end

    private

    def sanitize(value)
      value.to_s.gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    end
  end
end
