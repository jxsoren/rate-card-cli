# frozen_string_literal: true

require 'pathname'
require 'tty-prompt'

module RateCard
  # The prompt flow. Its only product is a validated RunSpec, and it is the only
  # place that reads user input. It makes exactly one network call — the
  # /services lookup that discovers which services can be offered.
  #
  # Returns nil if the user declines the final confirmation.
  class Wizard
    # Fallback only. Valid package types are a property of the service
    # (services[].package_types[].type), so the catalogue is preferred; this
    # covers a catalogue that reports none.
    PACKAGE_TYPES = %w[parcel flat_rate_envelope flat_rate_box soft_pack].freeze
    DEFAULT_WEIGHT_RANGE = '1-16'

    # Parses "1-8", "1,3,5" or a mix into a sorted unique Array<Integer>.
    def self.parse_range(input)
      input.to_s.split(',').flat_map do |part|
        part = part.strip
        if (match = part.match(/\A(\d+)\s*-\s*(\d+)\z/))
          low, high = match.captures.map(&:to_i)
          low <= high ? (low..high).to_a : []
        elsif part.match?(/\A\d+\z/)
          [part.to_i]
        else
          []
        end
      end.uniq.sort
    end

    def initialize(prompt:, ui:, output_base:, client_factory: ->(token) { Client.new(token: token) })
      @prompt = prompt
      @ui = ui
      @output_base = Pathname.new(output_base)
      @client_factory = client_factory
    end

    def run
      token = ask_token
      identity = Token.decode(token)
      @ui.customer_confirmed(**identity)

      services = discover_services(token)
      carrier = ask_carrier(services)
      selected = ask_services(services, carrier)

      spec = build_spec(token, identity, carrier, selected)
      @ui.recap(spec)
      return nil unless @prompt.yes?('Build this rate card?')

      spec.validate!
    end

    private

    # Re-prompts on a malformed token rather than exiting: a typo in a pasted
    # JWT should not cost the user the whole run.
    def ask_token
      loop do
        raw = @prompt.mask('eHub API token:').to_s.strip
        begin
          Token.decode(raw)
          return raw
        rescue Token::DecodeError => e
          @ui.error("#{e.message} — paste the token again")
        end
      end
    end

    # The service catalogue, not a rate call: it costs nothing and lists services
    # that would not have quoted at a single probe weight and zone.
    def discover_services(token)
      client = @client_factory.call(token)
      services = @ui.with_spinner('Loading available services') do
        ServiceCatalog.from_response(client.fetch_services)
      end

      raise NoServices, 'the API returned no services for this token' if services.empty?

      @ui.success("#{services.length} services found")
      services
    end

    def ask_carrier(services)
      carriers = ServiceCatalog.group_by_carrier(services).keys
      return carriers.first if carriers.length == 1

      @prompt.select('Carrier:', carriers)
    end

    def ask_services(services, carrier)
      choices = services.select { |service| service.carrier == carrier }
      selected = @prompt.multi_select('Services:', min: 1) do |menu|
        choices.each { |service| menu.choice service.label, service }
      end
      Array(selected)
    end

    def build_spec(token, identity, carrier, selected)
      zones = ask_zones(carrier)
      unit = @prompt.select('Weight unit:', %i[oz lbs])
      weights = ask_weights
      package_type = ask_package_type(selected)
      rate_keys = ask_rate_keys

      RunSpec.new(
        token: token,
        customer_name: identity[:name],
        customer_id: identity[:customer_id],
        carrier: carrier,
        services: selected,
        zones: zones,
        weight_unit: unit,
        weights: weights,
        package_type: package_type,
        rate_keys: rate_keys,
        output_base: @output_base,
        show_table: true,
        started_at: Time.now
      )
    end

    # The union of what the selected services accept, so a contract type like
    # fedex_pak is offered and a type no selected service accepts is not.
    def ask_package_type(selected)
      choices = selected.flat_map(&:package_types).uniq.sort
      choices = PACKAGE_TYPES if choices.empty?
      return choices.first if choices.length == 1

      @prompt.select('Package type:', choices)
    end

    def ask_zones(carrier)
      available = Constants::Addresses.available_zones(carrier)
      default = "#{available.first}-#{available.last}"

      loop do
        answer = @prompt.ask('Zones:', default: default)
        zones = self.class.parse_range(answer) & available
        return zones unless zones.empty?

        @ui.error("no valid zones in that input (available: #{default})")
      end
    end

    def ask_weights
      loop do
        answer = @prompt.ask('Weight range:', default: DEFAULT_WEIGHT_RANGE)
        weights = self.class.parse_range(answer).reject(&:zero?)
        return weights unless weights.empty?

        @ui.error('enter a range like 1-16 or a list like 1,4,8')
      end
    end

    # menu.default takes 1-based INDEXES. Passing `default: true` per choice
    # instead makes multi_select hang forever — verified against tty-prompt
    # 0.23.1 — so do not "simplify" this back to a per-choice default.
    def ask_rate_keys
      keys = RunSpec::RATE_KEY_FIELDS.keys
      selected = @prompt.multi_select('Rate columns:', min: 1) do |menu|
        menu.default(*(1..keys.length).to_a)
        keys.each { |key| menu.choice RunSpec::RATE_KEY_LABELS.fetch(key), key }
      end
      Array(selected)
    end
  end
end
