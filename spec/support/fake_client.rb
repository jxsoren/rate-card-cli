# frozen_string_literal: true

# Stands in for RateCard::Providers::EHub::Client with no network. Configure per-weight-and-zone
# rate behaviour with the block: either a service_rates array or an exception to
# raise. `services:` is what fetch_services returns (or raises), for the wizard's
# discovery call.
class FakeClient
  attr_reader :payloads

  def initialize(services: { 'services' => [] }, &responder)
    @services = services
    @responder = responder
    @payloads = []
    @mutex = Mutex.new
  end

  def fetch_services
    raise @services if @services.is_a?(Exception)

    @services
  end

  def fetch_rates(payload)
    @mutex.synchronize { @payloads << payload }

    parcel = payload[:shipment][:parcels].first
    postal = payload[:shipment][:to_location][:postal_code]
    result = @responder.call(parcel[:weight], postal)
    raise result if result.is_a?(Exception)

    result
  end
end
