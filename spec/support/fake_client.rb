# frozen_string_literal: true

# Stands in for RateCard::Providers::EHub::Client with no network. Configure per-weight-and-zone
# rate behaviour with the block: either a service_rates array or an exception to
# raise. `services:` is what fetch_services returns (or raises), for the wizard's
# discovery call.
class FakeClient
  attr_reader :payloads

  def initialize(services: { 'services' => [] }, zone_addresses: {}, &responder)
    @services = services
    @zone_addresses = zone_addresses
    @responder = responder
    @payloads = []
    @mutex = Mutex.new
  end

  def fetch_services
    raise @services if @services.is_a?(Exception)

    @services
  end

  # zone_addresses: keyed by service_id, each value either the parsed
  # { "zones" => {...} } body to return or an Exception to raise — same shape
  # convention as `services:` above.
  def fetch_zone_addresses(service_id, from_postal_code: nil)
    @last_from_postal_code = from_postal_code
    result = @zone_addresses.fetch(service_id) { { 'zones' => {} } }
    raise result if result.is_a?(Exception)

    result
  end

  attr_reader :last_from_postal_code

  def fetch_rates(payload)
    @mutex.synchronize { @payloads << payload }

    parcel = payload[:shipment][:parcels].first
    postal = payload[:shipment][:to_location][:postal_code]
    result = @responder.call(parcel[:weight], postal)
    raise result if result.is_a?(Exception)

    result
  end
end
