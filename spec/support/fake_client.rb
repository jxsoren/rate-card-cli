# frozen_string_literal: true

# Stands in for RateCard::Client with no network. Configure per-weight-and-zone
# behaviour: either a service_rates array or an exception to raise.
class FakeClient
  attr_reader :payloads

  def initialize(&responder)
    @responder = responder
    @payloads = []
    @mutex = Mutex.new
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
